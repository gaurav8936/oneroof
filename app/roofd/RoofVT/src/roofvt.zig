//! RoofVT: the C ABI roofd uses for one headless terminal per session (T14 §3b).
//! The only file that touches Ghostty's Zig VT API, which is not stable between tags: it builds from the same
//! pinned tag as GhosttyKit, so a Ghostty upgrade updates both together.
const std = @import("std");
const gvt = @import("ghostty-vt");

const alloc = std.heap.c_allocator;

/// Ghostty's read-only handler (state only), plus what roofd needs that it drops: the window title and the
/// queries a program is waiting on (answered by the holder while no terminal is attached).
const Handler = struct {
    inner: gvt.ReadonlyHandler,
    title: std.ArrayListUnmanaged(u8) = .{},
    queries: u32 = 0,
    /// Queries in the order the program sent them (it often ends a batch with DA1 and reads replies in order):
    /// 1 DA1 · 2 DSR 6 (cursor) · 3 DSR 5 · 4 OSC 10 (foreground) · 5 OSC 11 (background) · 6 kitty keyboard flags.
    order: [32]u8 = undefined,
    order_len: usize = 0,

    fn note(self: *Handler, code: u8) void {
        if (self.order_len < self.order.len) {
            self.order[self.order_len] = code;
            self.order_len += 1;
        }
    }

    pub fn deinit(self: *Handler) void {
        self.inner.deinit();
        self.title.deinit(alloc);
    }

    pub fn vt(self: *Handler, comptime action: gvt.StreamAction.Tag, value: gvt.StreamAction.Value(action)) !void {
        switch (action) {
            .window_title => {
                self.title.clearRetainingCapacity();
                try self.title.appendSlice(alloc, value.title);
            },
            .device_attributes => if (value == .primary) {
                self.queries |= 1;
                self.note(1);
            },
            .device_status => switch (value.request) {
                .cursor_position => {
                    self.queries |= 2;
                    self.note(2);
                },
                .operating_status => {
                    self.queries |= 4;
                    self.note(3);
                },
                else => {},
            },
            .kitty_keyboard_query => self.note(6),
            .color_operation => {
                var it = value.requests.constIterator(0);
                while (it.next()) |req| switch (req.*) {
                    .query => |target| switch (target) {
                        .dynamic => |d| switch (d) {
                            .foreground => self.note(4),
                            .background => self.note(5),
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                };
                try self.inner.vt(action, value);
            },
            else => try self.inner.vt(action, value),
        }
    }
};

const Rvt = struct {
    term: gvt.Terminal,
    stream: gvt.Stream(Handler),
};

fn bytesOut(slice: []u8, out: [*c][*c]u8) usize {
    out.* = slice.ptr;
    return slice.len;
}

fn copyOut(src: []const u8, out: [*c][*c]u8) usize {
    if (src.len == 0) {
        out.* = null;
        return 0;
    }
    const buf = alloc.dupe(u8, src) catch {
        out.* = null;
        return 0;
    };
    return bytesOut(buf, out);
}

export fn rvt_new(cols: u16, rows: u16, max_scrollback_bytes: usize) ?*Rvt {
    const r = alloc.create(Rvt) catch return null;
    r.term = gvt.Terminal.init(alloc, .{ .cols = cols, .rows = rows, .max_scrollback = max_scrollback_bytes }) catch {
        alloc.destroy(r);
        return null;
    };
    r.stream = gvt.Stream(Handler).initAlloc(alloc, .{ .inner = r.term.vtHandler() });
    return r;
}

export fn rvt_free(r: ?*Rvt) void {
    const t = r orelse return;
    t.stream.deinit();
    t.term.deinit(alloc);
    alloc.destroy(t);
}

export fn rvt_feed(r: *Rvt, bytes: [*c]const u8, len: usize) void {
    if (len == 0) return;
    r.stream.nextSlice(bytes[0..len]) catch {};
}

export fn rvt_resize(r: *Rvt, cols: u16, rows: u16) bool {
    r.term.resize(alloc, cols, rows) catch return false;
    return true;
}

/// Rows below the last row with text. The formatter trims them, which would leave a rebuilt screen one or more rows
/// lower than the real one (the next live output then overwrites a line); redraw puts them back.
fn trailingBlankRows(screen: *const gvt.Screen, rows: usize) usize {
    var y: usize = rows;
    while (y > 0) : (y -= 1) {
        const p = screen.pages.pin(.{ .active = .{ .x = 0, .y = @intCast(y - 1) } }) orelse continue;
        if (gvt.Cell.hasTextAny(p.cells(.all))) return rows - y;
    }
    return rows;
}

/// One screen's content, then its trimmed blank rows, so the bottom row of the rebuilt screen is the real one.
fn writeScreen(w: *std.Io.Writer, screen: *const gvt.Screen, rows: usize) !void {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    defer aw.deinit();
    // LAB-1550: keep soft wraps (a long line goes out as one line and the client wraps it again), so history the client
    // receives still reflows when its pane widens or narrows. Without it every wrap became a hard line break at attach,
    // and text stayed at the width it had then (a third of a wide pane).
    const sf: gvt.formatter.ScreenFormatter = .init(screen, .{ .emit = .vt, .unwrap = true });
    try aw.writer.print("{f}", .{sf});
    const body = aw.written();
    if (body.len == 0) return;
    try w.writeAll(body);
    for (0..trailingBlankRows(screen, rows)) |_| try w.writeAll("\r\n");
}

fn redraw(r: *Rvt) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const w = &aw.writer;
    const t = &r.term;
    const rows: usize = t.rows;
    // On the alternate screen (a full-screen agent), the primary screen goes first with its cursor, so leaving the
    // alternate screen later shows what came before, where it was.
    if (t.screens.active_key == .alternate) {
        if (t.screens.get(.primary)) |primary| {
            try writeScreen(w, primary, rows);
            try w.print("\x1b[0m\x1b[{d};{d}H", .{ primary.cursor.y + 1, primary.cursor.x + 1 });
        }
    }
    // 1. Palette and modes (this switches to the alternate screen when it is active).
    var head: gvt.formatter.TerminalFormatter = .init(t, .{ .emit = .vt });
    head.content = .none;
    head.extra = .none;
    head.extra.palette = true;
    head.extra.modes = true;
    try w.print("{f}", .{head});
    // 2. History and screen of the active screen, bottom-aligned.
    try writeScreen(w, t.screens.active, rows);
    // 3. Scroll region, tab stops, keyboard modes, pwd, then the screen's style, charsets and cursor.
    var tail: gvt.formatter.TerminalFormatter = .init(t, .{ .emit = .vt });
    tail.content = .none;
    tail.extra = .all;
    tail.extra.palette = false;
    tail.extra.modes = false;
    try w.print("{f}", .{tail});
    // Tab stops move the cursor (CSI G + HTS) after the cursor position was written: put it back.
    const c = t.screens.active.cursor;
    try w.print("\x1b[{d};{d}H", .{ c.y + 1, c.x + 1 });
    return try aw.toOwnedSlice();
}

export fn rvt_redraw(r: *Rvt, out: [*c][*c]u8) usize {
    const s = redraw(r) catch {
        out.* = null;
        return 0;
    };
    return bytesOut(s, out);
}

fn text(r: *Rvt, last_lines: u32) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(alloc);
    errdefer aw.deinit();
    const tf: gvt.formatter.TerminalFormatter = .init(&r.term, .{ .emit = .plain });
    try aw.writer.print("{f}", .{tf});
    const all = try aw.toOwnedSlice();
    if (last_lines == 0) return all;
    var n: u32 = 0;
    var i: usize = all.len;
    while (i > 0) : (i -= 1) {
        if (all[i - 1] == '\n') {
            n += 1;
            if (n == last_lines) break;
        }
    }
    if (i == 0) return all;
    defer alloc.free(all);
    return try alloc.dupe(u8, all[i..]);
}

export fn rvt_text(r: *Rvt, last_lines: u32, out: [*c][*c]u8) usize {
    const s = text(r, last_lines) catch {
        out.* = null;
        return 0;
    };
    return bytesOut(s, out);
}

export fn rvt_mode(r: *Rvt, mode: u16, ansi: bool) bool {
    const m = gvt.modes.modeFromInt(mode, ansi) orelse return false;
    return r.term.modes.get(m);
}

export fn rvt_title(r: *Rvt, out: [*c][*c]u8) usize {
    return copyOut(r.stream.handler.title.items, out);
}

export fn rvt_pwd(r: *Rvt, out: [*c][*c]u8) usize {
    return copyOut(r.term.getPwd() orelse "", out);
}

export fn rvt_cursor(r: *Rvt, x: *u16, y: *u16) bool {
    const c = r.term.screens.active.cursor;
    x.* = @intCast(c.x);
    y.* = @intCast(c.y);
    return r.term.screens.active_key == .alternate;
}

export fn rvt_take_queries(r: *Rvt) u32 {
    const q = r.stream.handler.queries;
    r.stream.handler.queries = 0;
    return q;
}

/// The queries since the last call, in order (codes above); returns how many were written to `out`.
export fn rvt_take_query_list(r: *Rvt, out: [*c]u8, cap: usize) usize {
    const h = &r.stream.handler;
    const n = @min(h.order_len, cap);
    for (0..n) |i| out[i] = h.order[i];
    h.order_len = 0;
    h.queries = 0;
    return n;
}

export fn rvt_bytes_free(bytes: [*c]u8, len: usize) void {
    if (bytes == null or len == 0) return;
    alloc.free(bytes[0..len]);
}

// MARK: Tests

fn feedStr(r: *Rvt, s: []const u8) void {
    rvt_feed(r, s.ptr, s.len);
}

fn takeText(r: *Rvt, lines: u32) ![]u8 {
    var p: [*c]u8 = null;
    const n = rvt_text(r, lines, &p);
    if (n == 0) return try alloc.dupe(u8, "");
    defer rvt_bytes_free(p, n);
    return try alloc.dupe(u8, p[0..n]);
}

test "feed, text, title, pwd, cursor" {
    const r = rvt_new(40, 5, 1 << 20).?;
    defer rvt_free(r);
    feedStr(r, "\x1b]0;my title\x07\x1b]7;file://host/tmp/x\x07one\r\ntwo\r\nthree");
    const t = try takeText(r, 2);
    defer alloc.free(t);
    try std.testing.expectEqualStrings("two\nthree", t);
    var p: [*c]u8 = null;
    const n = rvt_title(r, &p);
    defer rvt_bytes_free(p, n);
    try std.testing.expectEqualStrings("my title", p[0..n]);
    var x: u16 = 0;
    var y: u16 = 0;
    try std.testing.expect(!rvt_cursor(r, &x, &y));
    try std.testing.expectEqual(@as(u16, 5), x);
    try std.testing.expectEqual(@as(u16, 2), y);
}

test "queries are recorded, not answered" {
    const r = rvt_new(40, 5, 1 << 20).?;
    defer rvt_free(r);
    feedStr(r, "\x1b[c\x1b[6n");
    try std.testing.expectEqual(@as(u32, 3), rvt_take_queries(r));
    try std.testing.expectEqual(@as(u32, 0), rvt_take_queries(r));
}

test "queries keep their order (Codex: DSR 6, OSC 10, OSC 11, kitty, DA1)" {
    const r = rvt_new(40, 5, 1 << 20).?;
    defer rvt_free(r);
    feedStr(r, "\x1b[6n\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[?u\x1b[c");
    var out: [8]u8 = undefined;
    const n = rvt_take_query_list(r, &out, out.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 2, 4, 5, 6, 1 }, out[0..n]);
    try std.testing.expectEqual(@as(usize, 0), rvt_take_query_list(r, &out, out.len));
}

test "redraw rebuilds the same screen in a fresh terminal, both screens" {
    const a = rvt_new(30, 6, 1 << 20).?;
    defer rvt_free(a);
    var i: usize = 0;
    var buf: [32]u8 = undefined;
    while (i < 20) : (i += 1) feedStr(a, try std.fmt.bufPrint(&buf, "line {d}\r\n", .{i}));
    feedStr(a, "\x1b[1;31mred\x1b[0m $ ");
    feedStr(a, "\x1b[?2004h");
    var p: [*c]u8 = null;
    const n = rvt_redraw(a, &p);
    defer rvt_bytes_free(p, n);
    const b = rvt_new(30, 6, 1 << 20).?;
    defer rvt_free(b);
    rvt_feed(b, p, n);
    const ta = try takeText(a, 0);
    defer alloc.free(ta);
    const tb = try takeText(b, 0);
    defer alloc.free(tb);
    try std.testing.expectEqualStrings(ta, tb);
    try std.testing.expect(rvt_mode(b, 2004, false));
    var ax: u16 = 0;
    var ay: u16 = 0;
    var bx: u16 = 0;
    var by: u16 = 0;
    _ = rvt_cursor(a, &ax, &ay);
    _ = rvt_cursor(b, &bx, &by);
    try std.testing.expectEqual(ax, bx);
    try std.testing.expectEqual(ay, by);

    // Alternate screen: the agent's screen is shown, the primary history is kept underneath.
    feedStr(a, "\x1b[?1049h\x1b[2J\x1b[Hfull screen agent");
    var p2: [*c]u8 = null;
    const n2 = rvt_redraw(a, &p2);
    defer rvt_bytes_free(p2, n2);
    const c = rvt_new(30, 6, 1 << 20).?;
    defer rvt_free(c);
    rvt_feed(c, p2, n2);
    var cx: u16 = 0;
    var cy: u16 = 0;
    try std.testing.expect(rvt_cursor(c, &cx, &cy));
    const tc = try takeText(c, 0);
    defer alloc.free(tc);
    try std.testing.expect(std.mem.indexOf(u8, tc, "full screen agent") != null);
    feedStr(c, "\x1b[?1049l");
    const back = try takeText(c, 0);
    defer alloc.free(back);
    try std.testing.expect(std.mem.indexOf(u8, back, "line 3") != null);
}

test "redraw keeps blank rows under the cursor, so live output continues on the right row" {
    const a = rvt_new(20, 5, 1 << 20).?;
    defer rvt_free(a);
    feedStr(a, "1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n");   // cursor on an empty bottom row
    var p: [*c]u8 = null;
    const n = rvt_redraw(a, &p);
    defer rvt_bytes_free(p, n);
    const b = rvt_new(20, 5, 1 << 20).?;
    defer rvt_free(b);
    rvt_feed(b, p, n);
    feedStr(a, "7\r\n");
    feedStr(b, "7\r\n");
    const ta = try takeText(a, 0);
    defer alloc.free(ta);
    const tb = try takeText(b, 0);
    defer alloc.free(tb);
    try std.testing.expectEqualStrings(ta, tb);
}

test "resize reflows" {
    const r = rvt_new(20, 4, 1 << 20).?;
    defer rvt_free(r);
    feedStr(r, "abcdefghijklmnopqrstuvwxyz");
    try std.testing.expect(rvt_resize(r, 40, 4));
    const t = try takeText(r, 0);
    defer alloc.free(t);
    try std.testing.expectEqualStrings("abcdefghijklmnopqrstuvwxyz", t);
}

test "redraw keeps soft wraps, so the rebuilt history still reflows (LAB-1550)" {
    const a = rvt_new(20, 4, 1 << 20).?;
    defer rvt_free(a);
    feedStr(a, "abcdefghijklmnopqrstuvwxyz\r\nnext line\r\n");
    var p: [*c]u8 = null;
    const n = rvt_redraw(a, &p);
    defer rvt_bytes_free(p, n);
    const b = rvt_new(20, 4, 1 << 20).?;
    defer rvt_free(b);
    rvt_feed(b, p, n);
    const same = try takeText(b, 0);
    defer alloc.free(same);
    const orig = try takeText(a, 0);
    defer alloc.free(orig);
    try std.testing.expectEqualStrings(orig, same);
    try std.testing.expect(rvt_resize(b, 40, 4));
    const t = try takeText(b, 0);
    defer alloc.free(t);
    try std.testing.expect(std.mem.indexOf(u8, t, "abcdefghijklmnopqrstuvwxyz") != null);
}

