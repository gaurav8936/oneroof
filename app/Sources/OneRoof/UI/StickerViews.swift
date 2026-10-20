import AppKit
import SwiftUI
import OneRoofCore

extension Pastel {
    func fillColor(_ scheme: ColorScheme) -> Color { fill(dark: scheme == .dark).color }
    func inkColor(_ scheme: ColorScheme) -> Color { ink(dark: scheme == .dark).color }
}

/// A sticker in a dense pastel: Bold = solid pastel, Soft = lighter pastel with a pastel outline. Always with its icon.
struct StickerView: View {
    let sticker: Sticker
    var soft = false
    var size: CGFloat = 10.5
    var selected = true          // in pickers: an unselected sticker is drawn faint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = sticker.pastel.fillColor(scheme), ink = sticker.pastel.inkColor(scheme)
        HStack(spacing: 3) {
            Image(systemName: sticker.symbol).font(.system(size: size - 1, weight: .bold))
            Text(sticker.label).font(.system(size: size, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(soft && scheme == .dark ? fill : ink)
        .padding(.horizontal, size * 0.62)
        .padding(.vertical, size * 0.24)
        // In pickers, a sticker not chosen is an outline in its own colour at full strength (LAB-246: fading it to
        // 35% made it look disabled); chosen is filled.
        .background(Capsule().fill(selected ? (soft ? fill.opacity(scheme == .dark ? 0.16 : 0.55) : fill) : .clear))
        .overlay(Capsule().strokeBorder(selected ? (soft ? fill.opacity(0.9) : ink.opacity(0.12)) : ink.opacity(0.55), lineWidth: 1))
    }
}

/// The agent's logo: fixed per agent and never replaced, so every row says which agent it is at a glance.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 26
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = agent.logoPastel
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(p.fillColor(scheme))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(p.inkColor(scheme).opacity(0.18), lineWidth: 1)
            Image(systemName: agent.logoSymbol).font(.system(size: size * 0.48, weight: .heavy)).foregroundStyle(p.ink(dark: false).color)
        }
        .frame(width: size, height: size)
        .help(agent.displayName)
    }
}

/// Status as a small pill: dot + label in the status colour.
struct StatusPillV1: View {
    let status: SessionStatus
    let tokens: ThemeTokens

    var body: some View {
        let c = tokens.statusColor(status).color
        HStack(spacing: 4) {
            StatusDot(status: status, tokens: tokens).scaleEffect(0.8)
            Text(status.label).font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(c.opacity(0.13)))
    }
}

/// Toggle stickers on a session: every built-in one, the session's custom ones, and a field to add a new one.
struct StickerPicker: View {
    let current: [String]
    var soft = false
    let toggle: (String) -> Void
    @State private var custom = ""

    var body: some View {
        let ids = Set(current.map { Sticker.resolve($0).id })
        let customs = current.map(Sticker.resolve).filter { !$0.builtIn }
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(Sticker.catalog.filter { $0.id != "next" && $0.id != "dnu" } + customs) { s in
                    Button { toggle(s.id) } label: { StickerView(sticker: s, soft: soft, size: 11, selected: ids.contains(s.id)) }
                        .buttonStyle(.plain)
                        .help(ids.contains(s.id) ? "Remove \(s.label)" : "Add \(s.label)")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("New sticker…", text: $custom)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit {
                        let v = custom.trimmingCharacters(in: .whitespaces)
                        if !v.isEmpty, !ids.contains(v.lowercased()) { toggle(v) }
                        custom = ""
                    }
            }
        }
    }
}

/// Wrapping row layout for stickers.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 260
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

/// Catches a right click on a row (and lets every other click through) so it can open the colourful menu.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class Catcher: NSView {
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action?() }
        override func mouseDown(with event: NSEvent) { action?() }   // control-click
    }

    func makeNSView(context: Context) -> Catcher { let v = Catcher(); v.action = action; return v }
    func updateNSView(_ v: Catcher, context: Context) { v.action = action }
}

/// "3m", "2h", "4d": time since the session was last active.
func shortAgo(_ d: Date, now: Date = Date()) -> String {
    let s = max(0, now.timeIntervalSince(d))
    if s < 60 { return "now" }
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}


/// A seat's usage: name, a bar for the 5-hour window (the 7-day figure beside it), green → amber → coral.
struct SeatGaugeV1: View {
    let seat: SeatUsage
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let w = seat.worst ?? 0
        let p = Pastel.named(w >= 90 ? "coral" : w >= 70 ? "peach" : "mint")!
        if compact {
            Text("\(short) \(seat.fiveHour.map { "\(Int($0))%" } ?? "–")")
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(p.inkColor(scheme)).padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(p.fillColor(scheme)))
                .help(detail)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(seat.seat).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(p.fillColor(scheme)).frame(width: g.size.width * CGFloat(min(seat.fiveHour ?? 0, 100) / 100))
                        Capsule().strokeBorder(p.inkColor(scheme).opacity(0.25), lineWidth: 0.5)
                    }
                }
                .frame(height: 7)
            }
            .opacity(seat.stale ? 0.55 : 1)
        }
    }

    var short: String { seat.seat == "Claude1" ? "C1" : seat.seat == "Claude2" ? "C2" : seat.seat == "Codex" ? "CX" : seat.seat }

    var detail: String {
        var parts: [String] = []
        if let f = seat.fiveHour { parts.append("5h \(Int(f))%" + (seat.fiveHourResets.map { " · resets \($0.formatted(date: .omitted, time: .shortened))" } ?? "")) }
        if let s = seat.sevenDay { parts.append("7d \(Int(s))%") }
        if seat.stale { parts.append("old data") }
        return parts.joined(separator: " · ")
    }
}
