import SwiftUI
import OneRoofCore

/// The agent mark (COMPONENTS AgentBadge): a monogram squircle in the agent's colour, with an optional
/// status dot at the bottom-right ringed in the panel colour. Running dots pulse unless Reduce Motion is on.
struct AgentBadge: View {
    @Environment(\.theme) private var t
    let mark: AgentMark
    var size: CGFloat = 30
    var status: SessionStatus?
    /// Ring colour behind the status dot (the panel background).
    var ring: RGB?

    init(_ mark: AgentMark, size: CGFloat = 30, status: SessionStatus? = nil, ring: RGB? = nil) {
        self.mark = mark; self.size = size; self.status = status; self.ring = ring
    }

    init(item: BoardItem, size: CGFloat = 30, status: Bool = true, ring: RGB? = nil) {
        self.init(AgentMark(agent: item.session.agent, account: item.account), size: size, status: status ? item.status : nil, ring: ring)
    }

    private var radius: CGFloat {
        switch size {
        case ..<26: return 6
        case ..<30: return 7
        case ..<32: return 8
        case ..<40: return 9
        default: return 11
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(mark.fill(dark: t.isDark).color)
            .frame(width: size, height: size)
            .overlay(Text(mark.mono).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(mark.ink(dark: t.isDark).color))
            .overlay(alignment: .bottomTrailing) {
                if let status, size >= 20 {
                    StatusDot(status: status, size: 11, ring: ring ?? t.sidebar)
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(mark.mono + (status.map { ", " + StatusPalette.label($0) } ?? ""))
    }
}

/// One dot colour per state everywhere; Running has a halo that pulses 0→4 pt over 1.6 s.
struct StatusDot: View {
    @Environment(\.theme) private var t
    let status: SessionStatus
    var size: CGFloat = 8
    var ring: RGB?
    @State private var pulse = false

    init(status: SessionStatus, size: CGFloat = 8, ring: RGB? = nil) {
        self.status = status; self.size = size; self.ring = ring
    }
    /// v0.1 call sites.
    init(status: SessionStatus, tokens: ThemeTokens) { self.init(status: status, size: 8) }

    var body: some View {
        let c = t.statusColor(status).color
        ZStack {
            if status == .running && !Motion.reduce {
                Circle().fill(c.opacity(pulse ? 0 : 0.35))
                    .frame(width: size + (pulse ? 8 : 0), height: size + (pulse ? 8 : 0))
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }
            if let ring { Circle().fill(ring.color).frame(width: size + 4, height: size + 4) }
            switch status {
            case .planned, .next: Circle().strokeBorder(c, lineWidth: 1.5).frame(width: size, height: size)
            default: Circle().fill(c).frame(width: size, height: size)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

/// Capsule pill per status (COMPONENTS StatusPill): fill / text / edge from the theme; Parked strikes the label.
struct StatusPill: View {
    @Environment(\.theme) private var t
    let status: SessionStatus
    var label: String?
    var scheduled: String?

    var body: some View {
        let p = scheduled != nil ? StatusPalette.scheduledPill(theme: t.name) : t.pill(status)
        Text(scheduled.map { "⏱ " + $0 } ?? label ?? StatusPalette.label(status))
            .ui(10.5, .semibold)
            .strikethrough(p.edge == .strike)
            .foregroundStyle(p.text.color)
            .padding(.vertical, 1).padding(.horizontal, 7)
            .background(Capsule().fill(p.fill?.color ?? .clear))
            .overlay {
                switch p.edge {
                case .solid(let c): Capsule().strokeBorder(c.color, lineWidth: 1)
                case .dashed(let c): Capsule().strokeBorder(c.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                default: EmptyView()
                }
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Status: " + (label ?? StatusPalette.label(status)))
    }
}

/// One-line caption under a name (12 pt text2; needs → needs text; now → amber 500).
struct CaptionLine: View {
    @Environment(\.theme) private var t
    let caption: LiveCaption
    var size: CGFloat = TypeScale.caption

    var body: some View {
        Text(caption.text)
            .ui(size, caption.tone == .now ? .medium : .regular)
            .foregroundStyle(color)
            .lineLimit(1).truncationMode(.tail)
            .help(caption.text + " — " + caption.source)
    }
    private var color: Color {
        switch caption.tone {
        case .needs: return t.needsText.color
        case .now: return t.now.color
        case .normal: return t.text2.color
        }
    }
}

/// A sticker capsule (COMPONENTS Sticker): filled with the sticker colours, or a dashed suggestion.
struct StickerTag: View {
    @Environment(\.theme) private var t
    let sticker: Sticker
    var filled = true
    var size: CGFloat = 10.5

    var body: some View {
        let c = t.sticker(sticker.pastel)
        // Not applied = its colour as an outline, at full strength, so it reads as something to click (LAB-246: the
        // faint dashed grey looked disabled); applied = filled.
        Text(sticker.label)
            .ui(size, .semibold)
            .foregroundStyle(c.ink.color)
            .padding(.vertical, 1).padding(.horizontal, 6)
            .background(Capsule().fill(filled ? c.fill.color : .clear))
            .overlay { if !filled { Capsule().strokeBorder(c.ink.color.opacity(0.55), lineWidth: 1) } }
            .lineLimit(1).fixedSize()
            .accessibilityLabel("Sticker " + sticker.label)
    }
}

/// Seat usage (COMPONENTS SeatGauge): a 4 pt bar in the agent colour, a chip, or a card with a note line.
struct SeatGauge: View {
    @Environment(\.theme) private var t
    enum Style { case bar, chip, card }
    let mark: AgentMark
    let used: Double?
    var note: String?
    var style: Style = .bar

    var body: some View {
        switch style {
        case .chip:
            HStack(spacing: 4) {
                Circle().fill(mark.fill.color).frame(width: 7, height: 7)
                Text(mark.mono).ui(10.5, .semibold, mono: true).foregroundStyle(t.text.color)
                Text(used.map { "\(Int($0))%" } ?? "–").ui(10.5).foregroundStyle(t.text3.color)
            }
        case .bar, .card:
            VStack(alignment: .leading, spacing: 3) {
                if style == .bar { HStack(spacing: 3) {
                    Text(mark.mono).ui(10.5, .semibold).foregroundStyle(t.text.color).fixedSize()
                    Spacer(minLength: 1)
                    Text(used.map { "\(Int($0))%" } ?? "—").ui(10.5).foregroundStyle(t.text3.color).lineLimit(1).minimumScaleFactor(0.8)
                } }
                bar
                if style == .card, let note { Text(note).ui(11).foregroundStyle(t.text3.color).lineLimit(1) }
            }
        }
    }

    private var bar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(t.separator.color)
                RoundedRectangle(cornerRadius: 2).fill(mark.fill.color)
                    .frame(width: g.size.width * CGFloat(min(100, max(0, used ?? 0))) / 100)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(mark.mono) seat \(used.map { "\(Int($0)) percent used" } ?? "no usage feed")")
    }
}

/// A step list (COMPONENTS StepList): 14 pt circles; done filled, now amber ring, todo grey ring.
struct StepList: View {
    @Environment(\.theme) private var t
    struct Step: Identifiable, Equatable {
        enum State { case done, now, todo }
        var id: Int
        var title: String
        var note: String?
        var state: State
    }
    let steps: [Step]
    /// Cap (LAB-259): more steps than this scroll inside the list, which keeps showing the current one.
    var maxVisible: Int?
    /// The step the terminal is rewound to (highlighted), and what a click on a step does.
    var selected: Int?
    var onTap: ((Int) -> Void)?
    /// Something at the end of a row (the Explain button).
    var accessory: ((Step) -> AnyView)?

    private static let rowHeight: CGFloat = 25

    var body: some View {
        if let cap = maxVisible, steps.count > cap {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { list.padding(.trailing, 6) }
                    .frame(height: CGFloat(cap) * Self.rowHeight)
                    .onAppear { proxy.scrollTo(focus, anchor: .bottom) }
                    .onChange(of: focus) { _, f in withAnimation(Motion.fast) { proxy.scrollTo(f, anchor: selected == nil ? .bottom : .center) } }
            }
        } else {
            list
        }
    }

    /// The row to keep in view: the rewound-to step, else the current one, else the last.
    private var focus: Int? { selected ?? steps.first { $0.state == .now }?.id ?? steps.last?.id }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { s in
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        switch s.state {
                        case .done: Circle().fill(t.statusColor(.done).color)
                        case .now: Circle().strokeBorder(t.now.color, lineWidth: 2)
                        case .todo: Circle().strokeBorder(t.separatorStrong.color, lineWidth: 2)
                        }
                    }
                    .frame(width: 14, height: 14)
                    (Text(s.title).foregroundColor(t.text.color) + Text(s.note.map { " · " + $0 } ?? "").foregroundColor(t.text3.color))
                        .ui(13).lineLimit(1)
                    Spacer(minLength: 4)
                    if let accessory { accessory(s) }
                }
                .frame(height: Self.rowHeight)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected == s.id ? t.selection.color : .clear))
                .contentShape(Rectangle())
                .onTapGesture { onTap?(s.id) }
                .help(onTap == nil ? "" : (selected == s.id ? "Back to the current step" : "Rewind the terminal to this step"))
                .accessibilityElement(children: .combine)
                .id(s.id)
            }
        }
    }
}

/// Thin separator line in a theme.
struct Hairline: View {
    @Environment(\.theme) private var t
    var strong = false
    var body: some View { Rectangle().fill((strong ? t.separatorStrong : t.separator).color).frame(height: 1) }
}

/// Relative age: "20s", "3m", "1h", "2d".
func ageText(_ d: Date?, now: Date = Date()) -> String {
    guard let d else { return "" }
    let s = Int(now.timeIntervalSince(d))
    switch s {
    case ..<60: return "\(max(s, 0))s"
    case ..<3600: return "\(s / 60)m"
    case ..<86400: return "\(s / 3600)h"
    default: return "\(s / 86400)d"
    }
}

/// The × at the top right of a side panel: closes that panel (same as its toolbar toggle and View menu item).
struct PanelCloseButton: View {
    @Environment(\.theme) private var t
    let title: String
    let action: Selector

    var body: some View {
        Button { NSApp.sendAction(action, to: nil, from: nil) } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.text2.color)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.control.color))
        }
        .buttonStyle(.plain).help("Close the \(title)").accessibilityLabel("Close the \(title)")
    }
}

/// A colour choice (LAB-246): big enough to see, outlined so pale pastels still show, and the chosen one gets an
/// accent ring and a check. `pastel == nil` is "no colour".
struct ColourSwatch: View {
    @Environment(\.theme) private var t
    @Environment(\.colorScheme) private var scheme
    let pastel: Pastel?
    var selected = false
    var size: CGFloat = 22
    @State private var hover = false

    var body: some View {
        ZStack {
            if let p = pastel {
                Circle().fill(p.fillColor(scheme))
                Circle().strokeBorder(p.inkColor(scheme).opacity(0.45), lineWidth: 1.5)
                if selected { Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .heavy)).foregroundStyle(p.inkColor(scheme)) }
            } else {
                Circle().strokeBorder(t.text2.color, lineWidth: 1.5)
                Image(systemName: selected ? "checkmark" : "slash.circle").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(t.text2.color)
            }
        }
        .frame(width: size, height: size)
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? t.accent.color : (hover ? t.separatorStrong.color : .clear), lineWidth: 2.5))
        .onHover { hover = $0 }
        .contentShape(Circle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
