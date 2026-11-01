import AppKit
import SwiftUI
import OneRoofCore

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

extension ThemeName {
    var colorScheme: ColorScheme { isDark ? .dark : .light }
    var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }
}

// MARK: Environment (APPEARANCE §2: each panel sets its own theme)

private struct ThemeKey: EnvironmentKey { static let defaultValue = ThemeName.daylight.tokens }
private struct TextScaleKey: EnvironmentKey { static let defaultValue = 1.0 }

extension EnvironmentValues {
    /// The theme of the panel this view is in.
    var theme: ThemeTokens {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
    /// UI text scale of the window (⌘+ ⌘− ⌘0), 0.85–1.3.
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

extension View {
    /// Draw this subtree in a theme: tokens, colour scheme for system controls, and text scale.
    func themed(_ t: ThemeName, scale: Double = 1) -> some View {
        environment(\.theme, t.tokens).environment(\.colorScheme, t.colorScheme).environment(\.textScale, scale)
    }

    /// A type-scale font (APPEARANCE §4) that follows the window's text size.
    func ui(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: weight, mono: mono))
    }
}

struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    var size: CGFloat
    var weight: Font.Weight
    var mono: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: mono ? .monospaced : .default))
    }
}

/// Type scale (tokens.json `type.scale`).
enum TypeScale {
    static let display: CGFloat = 28, title: CGFloat = 20, section: CGFloat = 15, body: CGFloat = 13.5
    static let row: CGFloat = 13.5, small: CGFloat = 12.5, caption: CGFloat = 12, micro: CGFloat = 11
    static let monoBody: CGFloat = 12.5, monoSmall: CGFloat = 11
}

/// Radii (tokens.json `radius`).
enum Radius {
    static let window: CGFloat = 12, card: CGFloat = 12, sheet: CGFloat = 14, row: CGFloat = 9, button: CGFloat = 7
    static let field: CGFloat = 8, squircle20: CGFloat = 6, squircle30: CGFloat = 8, squircle40: CGFloat = 11
}

/// Motion (tokens.json `motion`), off with Reduce Motion.
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var fast: Animation? { reduce ? nil : .easeOut(duration: 0.12) }
    static var base: Animation? { reduce ? nil : .easeOut(duration: 0.18) }
    static var slow: Animation? { reduce ? nil : .easeOut(duration: 0.28) }
}

/// Uppercase micro label (11/600 +0.06em, text3).
struct MicroLabel: View {
    @Environment(\.theme) private var t
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).ui(TypeScale.micro, .semibold).tracking(0.66).foregroundStyle(t.text3.color)
    }
}

/// Hover = selection at 50%, pressed = selection (AGENT_RULES §4).
struct HoverHighlight: ViewModifier {
    @Environment(\.theme) private var t
    @State private var hover = false
    var radius: CGFloat = Radius.row
    var selected = false
    /// LAB-2052 · the row's background when known: hover is then drawn at ≥ 1.3:1 against it (ResourceMarks.hover).
    var over: RGB? = nil
    /// Self-tests: draw as hovered.
    var forced = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? t.selection.color : ((hover || forced) ? hoverColour : .clear)))
            .onHover { hover = $0 }
    }
    private var hoverColour: Color {
        guard let over else { return t.selection.color.opacity(0.5) }
        return ResourceMarks.hover(over: over, dark: t.isDark).color
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = Radius.row, selected: Bool = false) -> some View {
        modifier(HoverHighlight(radius: radius, selected: selected))
    }
    /// LAB-2052 · a hover you can see (≥ 1.3:1) on a row whose background is `bg`.
    func hoverHighlight(over bg: RGB, radius: CGFloat = Radius.row, forced: Bool = false) -> some View {
        modifier(HoverHighlight(radius: radius, over: bg, forced: forced))
    }
}

/// A plain button style that shows pressed with the selection token.
struct PressStyle: ButtonStyle {
    @Environment(\.theme) private var t
    var radius: CGFloat = Radius.button
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(configuration.isPressed ? t.selection.color : .clear))
            .contentShape(Rectangle())
    }
}

/// Primary (accent) and secondary buttons (radius 7, 12.5/600).
struct RoofButton: View {
    @Environment(\.theme) private var t
    enum Kind { case primary, secondary, plain, danger }
    @Environment(\.isEnabled) private var enabled
    let title: String
    var kind: Kind = .secondary
    var action: () -> Void
    init(_ title: String, _ kind: Kind = .secondary, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).ui(TypeScale.small, .semibold).lineLimit(1)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .foregroundStyle(fg)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(kind == .secondary ? t.separatorStrong.color : .clear, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.4)   // owner 10-18: a greyed-out primary still looked clickable
        .accessibilityLabel(title)
    }
    private var fg: Color {
        switch kind {
        case .primary: return t.onAccent.color
        case .danger: return t.needsText.color
        case .plain: return t.accentText.color
        case .secondary: return t.text.color
        }
    }
    private var bg: Color {
        switch kind {
        case .primary: return t.accent.color
        case .secondary: return t.surface.color
        default: return .clear
        }
    }
}

/// Small rounded label used for agent/account/workstream tags (v0.1 views still being restyled use it).
struct Chip: View {
    let text: String
    let fg: Color
    let bg: Color
    var mono = false

    var body: some View {
        Text(text)
            .font(mono ? .system(size: 10, weight: .semibold, design: .monospaced) : .system(size: 10, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
            .lineLimit(1)
    }
}

/// v0.1 status token names, read from the v2 status palette (views being restyled still use them).
extension ThemeTokens {
    var statusNeedsYou: RGB { needsText }
    var statusRunning: RGB { accentText }
}

// `card` and `statusDone` live in OneRoofCore (History.swift, LAB-2045), so the History styles can be contrast-tested.
