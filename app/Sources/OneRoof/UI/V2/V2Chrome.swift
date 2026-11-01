import AppKit
import SwiftUI
import OneRoofCore

// One Roof 1.x window chrome (handover A1, shared/NAVIGATION.md, FOCUS_LADDER.md): the places rail and icon row, the
// status dock in its three forms, and the small pieces they share. Colours come only from the panel's theme tokens.

// MARK: Places

extension Place {
    /// The 0.5 centre view a place opens until its own v2 screen lands (M4 redraws Home, Needs you, Work, Machine,
    /// Loops; Learn stays today's Learn in the v2 frame). Nothing that works today is lost in the meantime.
    var centre: CentreView {
        switch self {
        case .home: return .overview
        case .needsYou: return .decisions
        case .sessions: return .workspace
        case .work: return .work
        case .machine: return .resources
        case .loops: return .loops
        case .learn: return .learn
        }
    }
}

extension CentreView {
    /// The place a centre view belongs to (menus such as ⇧⌘L Overview or ⌘B Board still open their view; the rail
    /// follows). Views of a session (editor, review, subagents, objective) stay in the place you were in.
    var place: Place? {
        switch self {
        case .workspace, .catalog: return .sessions   // LAB-1509: the catalog belongs to Sessions
        case .overview: return .home
        case .decisions: return .needsYou
        case .work, .board: return .work
        case .resources: return .machine
        case .loops: return .loops
        case .learn: return .learn
        case .subagents, .objective, .editor, .review: return nil
        }
    }
}

/// Live counts the chrome shows (needs you, tonight), shared by the rail, the icon row, the avatars and the dock.
enum V2Counts {
    @MainActor static func needsYou(_ model: AppModel) -> Int {
        model.needsYouBadge   // LAB-1933
    }
    @MainActor static func tonight(_ model: AppModel) -> Int {
        model.scheduleRecords.values.filter { if case .tonight = $0.schedule { return true }; if case .nightly = $0.schedule { return true }; return false }.count
    }
}

/// The 66 pt place rail (steps 0 and 2): icon + label per place, Needs you badged, Look at the foot; at step 2 the
/// seat bars sit above Look instead of a dock.
struct V2Rail: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Place.allCases) { p in
                V2PlaceButton(place: p, selected: win.place == p && !controller.v2OnPage, badge: p == .needsYou ? V2Counts.needsYou(model) : 0,
                              labelled: true) { controller.v2Open(p) }
            }
            Spacer(minLength: 8)
            StepReader(step: win.step) { s in   // LAB-1736: only this part follows the step
                if s.focusStep == .wide { V2RailSeats(model: model) { controller.v2OpenSettings(tab: 2) }.padding(.bottom, 6) }
            }
            Button { controller.v2ShowLooks() } label: {
                VStack(spacing: 3) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 19, weight: .medium))
                        .foregroundStyle(t.accentText.color).frame(height: 22)   // LAB-2002: as the places above
                    Text("Look").ui(10.5)
                }
                .foregroundStyle(t.text2.color).frame(minWidth: 54, maxWidth: .infinity, minHeight: 44, maxHeight: 44).padding(.horizontal, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Look: one preset sets every panel at once (Settings › Appearance)")
            .accessibilityLabel("Look")
        }
        .padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.control.color)
    }
}

/// The icon row (step 1): the seven places as icons in the toolbar band of the session column.
struct V2PlacesIconRow: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Place.allCases) { p in
                V2PlaceButton(place: p, selected: win.place == p && !controller.v2OnPage, badge: p == .needsYou ? V2Counts.needsYou(model) : 0,
                              labelled: false) { controller.v2Open(p) }
            }
        }
    }
}

struct V2PlaceButton: View {
    @Environment(\.theme) private var t
    let place: Place
    let selected: Bool
    let badge: Int
    let labelled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                // LAB-2002: bigger icons in the accent text colour so they read at a glance; the label keeps its size and
                // grey, and the frames below are unchanged, so the rail and the toolbar row keep their widths.
                Image(systemName: place.symbol).font(.system(size: labelled ? 19 : 15, weight: selected ? .semibold : .medium))
                    .foregroundStyle(t.accentText.color)
                    .frame(height: labelled ? 22 : 18)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)").ui(9, .bold).foregroundStyle(t.onAccent.color)
                                .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                                .background(Capsule().fill(t.statusColor(.needsYou).color))
                                .offset(x: labelled ? 11 : 9, y: labelled ? -6 : -7)
                        }
                    }
                if labelled { Text(place.title).ui(10.5, selected ? .semibold : .regular).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .foregroundStyle(selected ? t.text.color : t.text2.color)
            .frame(minWidth: labelled ? 56 : 26, maxWidth: labelled ? .infinity : 26, minHeight: labelled ? 44 : 24, maxHeight: labelled ? 44 : 24)
            .padding(.horizontal, labelled ? 5 : 0)   // LAB-1829: a wider rail gives the label room
            .background(RoundedRectangle(cornerRadius: labelled ? 9 : 7, style: .continuous)
                .fill(selected ? t.surface.color : .clear)
                .shadow(color: selected ? t.separator.color : .clear, radius: 0.5, y: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The icon row sits in the toolbar, where only an AppKit tooltip shows (LAB-1236); the rail is in the window.
        .modifier(PlaceHelp(text: place.title + " (⌃⌘\(place.controlKey))", inToolbar: !labelled))
        .accessibilityLabel(place.title + (badge > 0 ? ", \(badge) waiting" : "") + (selected ? ", selected" : ""))
    }
}

private struct PlaceHelp: ViewModifier {
    let text: String
    let inToolbar: Bool
    func body(content: Content) -> some View {
        if inToolbar { content.barHelp(text) } else { content.help(text) }
    }
}

// MARK: Dock

/// One seat in the dock: badge, then usage ("9% · 5h"), dimmed when the seat is off.
struct V2SeatChip: View {
    @Environment(\.theme) private var t
    let mark: SeatMark
    let usage: SeatUsage?
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            AgentBadge(mark, size: compact ? 16 : 20)
            Text(Self.label(usage, mark: mark)).ui(compact ? 10.5 : 11).foregroundStyle(usage == nil ? t.text3.color : t.text2.color).lineLimit(1).fixedSize()
        }
        .opacity(usage == nil ? 0.55 : 1)
        .help(Self.help(mark, usage))
    }

    static func label(_ u: SeatUsage?, mark: SeatMark? = nil) -> String {
        guard let u else { return mark.map { DockSeats.usageName($0) == nil } == true ? "ready" : "off" }
        if let f = u.fiveHour { return "\(Int(f))% · 5h" }
        if let w = u.sevenDay { return "\(Int(w))% · week" }
        return "–"
    }

    static func help(_ m: SeatMark, _ u: SeatUsage?) -> String {
        let who = m.accountID.map { "\(m.mono) · " + AgentAccounts.label(of: $0, agent: m.agent) } ?? m.mono
        guard let u else {
            return DockSeats.usageName(m) == nil ? "\(who): set up; this agent has no usage feed" : "\(who): not signed in or no usage feed"
        }
        var parts: [String] = []
        if let f = u.fiveHour { parts.append("5 h \(Int(f))%") }
        if let w = u.sevenDay { parts.append("7 d \(Int(w))%") }
        if let r = u.fiveHourResets { parts.append("resets \(r.formatted(date: .omitted, time: .shortened))") }
        return "\(u.seat): " + parts.joined(separator: " · ")
    }
}

/// LAB-1998: one list of seats for the dock, its compact line and the rail: the agents set up on this Mac, minus the
/// ones hidden in Settings › Seats & accounts (was a fixed C1 · C2 · CX · KM · GM).
enum V2Seats {
    @MainActor static func marks(_ model: AppModel) -> [SeatMark] { model.dockMarks }
    @MainActor static func usage(_ model: AppModel) -> [SeatMark: SeatUsage] {
        let byName = Dictionary(model.seats.map { ($0.seat, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [SeatMark: SeatUsage] = [:]
        for m in marks(model) { if let n = DockSeats.usageName(m), let u = byName[n] { out[m] = u } }
        return out
    }
}

/// The full dock (step 0, 50 pt across the window): seats · roofd · foundations · Mac load · Needs you · Tonight.
/// Every part opens where its details are (LAB-1085).
struct V2Dock: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var resources: ResourceMonitor
    let controller: MainWindowController

    var body: some View { watchedBody.modifier(WatchesResources(res: resources)) }   // LAB-1333
    @ViewBuilder private var watchedBody: some View {
        let usage = V2Seats.usage(model)
        // A narrow window (LAB-831): compact seat chips, then no Mac line, then no seats (Settings › Seats and the
        // Machine place have them); the status and the two pills always show, nothing spills past the edges.
        ViewThatFits(in: .horizontal) {
            ForEach(0..<4) { level in row(usage: usage, level: level) }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.control.color)
        .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }
}

extension V2Dock {
    /// The dock at a narrowness level: 0 everything, 1 compact seats, 2 no Mac line, 3 status and pills only.
    private func row(usage: [SeatMark: SeatUsage], level: Int) -> some View {
        HStack(spacing: level == 0 ? 14 : 10) {
            if level < 3 {
                ForEach(V2Seats.marks(model), id: \.self) { m in
                    Button { controller.v2OpenSettings(tab: 2) } label: { V2SeatChip(mark: m, usage: usage[m], compact: level >= 1) }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: level == 3 ? 0 : 12)
            V2DockStatus(model: model, controller: controller)
            if level < 2 {
                Button { controller.v2Open(.machine) } label: {
                    Text(V2DockMac.text(resources.snapshot)).ui(11).foregroundStyle(t.text2.color).lineLimit(1).fixedSize()
                }
                .buttonStyle(.plain).help("This Mac: One Roof's memory and CPU (Machine)")
            }
            V2DockPill(title: "Needs you", count: V2Counts.needsYou(model), urgent: true) { controller.v2Open(.needsYou) }
            V2DockPill(title: "Tonight", count: V2Counts.tonight(model), urgent: false) { controller.v2Open(.loops) }
        }
    }
}

/// "● roofd 0.5.2.9 · 4 agents · 1 foundations issue": the runtime and the startup check.
struct V2DockStatus: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let controller: MainWindowController

    var body: some View {
        HStack(spacing: 5) {
            Button { controller.v2Open(.machine) } label: {
                HStack(spacing: 5) {
                    Circle().fill(t.statusColor(model.runtimeOK ? .done : .needsYou).color).frame(width: 7, height: 7)
                    Text(model.runtimeState).ui(11).foregroundStyle(t.text2.color).lineLimit(1)
                    if let note = AppVersion.daemonOlderNote(model.daemonVersion, app: AppVersion.current?.short) {
                        Text("· older than app").ui(11).foregroundStyle(t.text3.color).lineLimit(1).fixedSize().help(note)
                    }
                }
            }
            .buttonStyle(.plain).help("roofd, the background service that keeps every session running (Machine)")
            let issues = model.foundations.filter { $0.level != .ok }.count
            if model.checkingFoundations {
                Text("· Checking…").ui(11).foregroundStyle(t.text3.color).fixedSize()
            } else if issues > 0 {
                Button { NotificationCenter.default.post(name: .openFoundations, object: nil) } label: {
                    Text("· \(issues) foundations issue\(issues == 1 ? "" : "s")").ui(11, .medium).foregroundStyle(t.needsText.color).fixedSize()
                }
                .buttonStyle(.plain).help("Startup check found problems (⇧⌘F)")
            }
        }
    }
}

enum V2DockMac {
    static func text(_ s: ResourceSnapshot) -> String {
        guard s.processCount > 0 else { return "Mac · measuring…" }
        return "Mac · \(ResourceFormat.bytes(s.footprint)) · \(ResourceFormat.cpu(s.cpu)) CPU"
    }
}

struct V2DockPill: View {
    @Environment(\.theme) private var t
    let title: String
    let count: Int
    let urgent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) · \(count)").ui(11, count > 0 ? .semibold : .regular)
                .foregroundStyle(urgent && count > 0 ? t.pill(.needsYou).text.color : t.text.color)
                .padding(.horizontal, 10).frame(height: 22)
                .background(Capsule().fill(urgent && count > 0 ? (t.pill(.needsYou).fill ?? t.surface).color : t.surface.color))
                .overlay(Capsule().strokeBorder(t.separator.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(count)")
    }
}

/// The dock folded into one line at the foot of the session column (step 1): "● roofd · C1 9% C2 5% CX 19%   ⌃⌘J".
struct V2DockLine: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let controller: MainWindowController
    @State private var flash = false

    var body: some View {
        let usage = V2Seats.usage(model)
        let needs = V2Counts.needsYou(model)
        HStack(spacing: 6) {
            Button { controller.v2Open(.machine) } label: {
                HStack(spacing: 4) {
                    Circle().fill(t.statusColor(model.runtimeOK ? .done : .needsYou).color).frame(width: 7, height: 7)
                    Text("roofd").ui(11).foregroundStyle(t.text2.color)
                }
            }
            .buttonStyle(.plain).help(model.runtimeState)
            let seats = V2Seats.marks(model).filter { usage[$0] != nil }
            if !seats.isEmpty { Text("·").ui(11).foregroundStyle(t.text3.color) }   // no dangling dot without seats
            ForEach(seats, id: \.self) { m in
                Text("\(m.mono) \(usage[m]?.worst.map { "\(Int($0))%" } ?? "–")").ui(11).foregroundStyle(t.text2.color)
                    .lineLimit(1).fixedSize().help(V2SeatChip.help(m, usage[m]))
            }
            if needs > 0 {
                Button { controller.v2Open(.needsYou) } label: {
                    Text("· Needs you \(needs)").ui(11, .semibold).foregroundStyle(t.needsText.color).fixedSize()
                }
                .buttonStyle(.plain)
            }
            // The startup check stays visible at step 1 when it found something (0.5.2.9's footer always showed it).
            let issues = model.foundations.filter { $0.level != .ok }.count
            if issues > 0 {
                Button { NotificationCenter.default.post(name: .openFoundations, object: nil) } label: {
                    Text("· \(issues) issue\(issues == 1 ? "" : "s")").ui(11, .medium).foregroundStyle(t.needsText.color).fixedSize()
                }
                .buttonStyle(.plain).help("Startup check found problems (⇧⌘F)")
            }
            Spacer(minLength: 4)
            Button { controller.v2ToggleDock() } label: { Text("⌃⌘J").ui(10.5).foregroundStyle(t.text3.color) }
                .buttonStyle(.plain).help("Show the full dock (⌃⌘J)")
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(flash ? t.selection.color : .clear)
        .onChange(of: needs) { old, new in
            // Needs you is never hidden: at step 1 the dock line flashes once when something starts waiting.
            guard new > old, !Motion.reduce else { return }
            withAnimation(.easeInOut(duration: 0.25)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeInOut(duration: 0.4)) { flash = false } }
        }
    }
}

/// Seat bars at the foot of the rail (step 2, where there is no dock). LAB-1266: one button that opens Settings ›
/// Seats & accounts (as the dock's seat chips do), each bar labelled with its seat (C1 · C2 · CX …), one tooltip for
/// the block, keyboard focusable with the accent ring.
struct V2RailSeats: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let open: () -> Void
    @State private var hover = false
    @FocusState private var focused: Bool

    static let help = "Seats: usage this window — open Seats & accounts"

    /// "C1 12%, C2 off, …" for VoiceOver (the bars carry no text of their own).
    static func spoken(_ marks: [SeatMark], _ usage: [SeatMark: SeatUsage]) -> String {
        marks.map { m in usage[m].map { "\(m.mono) \(Int($0.worst ?? 0))%" } ?? "\(m.mono) off" }.joined(separator: ", ")
    }

    var body: some View {
        let usage = V2Seats.usage(model)
        let marks = V2Seats.marks(model)
        Button(action: open) {
            VStack(spacing: 3) {
                ForEach(marks, id: \.self) { m in
                    HStack(spacing: 3) {
                        Text(m.mono).font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(usage[m] == nil ? t.text3.color : t.text2.color)
                            .frame(width: 14, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(t.separator.color)
                                Capsule().fill(m.fill.color).frame(width: g.size.width * CGFloat(min(100, max(0, usage[m]?.worst ?? 0))) / 100)
                            }
                        }
                        .frame(width: 30, height: 3)
                    }
                    .frame(height: 9)
                }
                Text("seats").ui(9.5).foregroundStyle(hover ? t.text2.color : t.text3.color)
            }
            .padding(.vertical, 5).frame(width: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(RailSeatsStyle(hover: hover))
        .focused($focused)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.accent.color, lineWidth: 2).padding(-2).opacity(focused ? 1 : 0))
        .onHover { hover = $0 }
        .help(Self.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seats: " + Self.spoken(marks, usage))
        .accessibilityHint("Opens Settings, Seats & accounts")
        .accessibilityAddTraits(.isButton)
    }

    private struct RailSeatsStyle: ButtonStyle {
        @Environment(\.theme) private var t
        let hover: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(configuration.isPressed ? t.selection.color : hover ? t.selection.color.opacity(0.5) : .clear))
        }
    }
}

// MARK: Shared bits

/// The Plan inspector folded to a 28 pt edge tab (steps 1 and 2): vertical "Plan ⌥⌘P · Ticket · Notes".
struct V2InspectorEdgeTab: View {
    @Environment(\.theme) private var t
    let open: (Int) -> Void

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(["Plan ⌥⌘P", "Ticket", "Notes"].enumerated()), id: \.offset) { i, s in
                Button { open(i) } label: {
                    Text(s).ui(10.5, i == 0 ? .semibold : .regular).foregroundStyle(i == 0 ? t.text.color : t.text2.color)
                        .fixedSize().rotationEffect(.degrees(90)).frame(width: 20, height: CGFloat(s.count) * 7 + 8)
                }
                .buttonStyle(.plain)
                .help(i == 0 ? "Slide the Plan over the terminal (⌥⌘P)" : "Open the Plan on its \(s) tab")
            }
            Spacer()
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surface.color)
        .overlay(alignment: .leading) { Rectangle().fill(t.separator.color).frame(width: 1) }
    }
}

/// "Focus · ⌥⌘F leaves · ⇧⌥⌘F steps back · hover the left edge for sessions" (step 3).
struct V2FocusHint: View {
    @Environment(\.theme) private var t
    var body: some View {
        Text("Focus · ⌥⌘F leaves · ⇧⌥⌘F steps back · hover the left edge for sessions")
            .ui(11).foregroundStyle(t.text2.color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(t.surface.color.opacity(0.92)))
            .overlay(Capsule().strokeBorder(t.separator.color, lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// Shows the Focus hint at step 3, for a few seconds after Focus starts, then fades it (LAB-1298: it sat between the
/// agent's prompt and the composer for as long as Focus lasted).
struct V2FocusHintSlot: View {
    @ObservedObject var win: WindowState
    @ObservedObject private var step: WindowStep   // LAB-1736
    @State private var shown = false
    init(win: WindowState) { self.win = win; _step = ObservedObject(wrappedValue: win.step) }
    var body: some View {
        Group {
            if win.focusStep == .focus && shown { V2FocusHint().transition(.opacity) } else { Color.clear.frame(width: 1, height: 1) }
        }
        .task(id: win.focusStep == .focus) {
            guard win.focusStep == .focus else { shown = false; return }
            shown = true
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.6)) { shown = false }
        }
    }
}

/// A hosting view that never takes the mouse (the hint over the terminal must not steal clicks or selection).
final class PassThroughHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The Always-allow Undo toast on the terminal card (CAP-26): "Always allow <pattern> in <repo> · Undo".
struct V2UndoToastSlot: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let windowId: String
    var body: some View {
        if let u = model.v2UndoRule, u.window == windowId {
            let d = u.decision
            HStack(spacing: 12) {
                Text("Always allow \(d.pattern) in \(d.repo)").ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                Button { model.removeRule(pattern: d.pattern, repo: d.repo); model.v2UndoRule = nil } label: {
                    Text("Undo").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(t.surface.color))
            .overlay(Capsule().strokeBorder(t.separator.color, lineWidth: 1))
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
