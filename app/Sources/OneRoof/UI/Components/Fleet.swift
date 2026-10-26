import SwiftUI
import OneRoofCore

/// The frame of a fleet view (Overview, Board, Decisions, Subagents): desk gradient, padding 22×28, a 28/600 title
/// with a subtitle, and a control on the right.
/// True inside the One Roof 1 (v2) window's centre: pages draw flat, on the centre's colour, as the handover does.
private struct V2WindowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var v2Window: Bool { get { self[V2WindowKey.self] } set { self[V2WindowKey.self] = newValue } }
}

struct FleetPage<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).ui(TypeScale.display, .semibold).tracking(-0.5).foregroundStyle(t.text.color)
                    Text(subtitle).ui(14).foregroundStyle(t.text2.color).lineLimit(1)
                }
                Spacer()
                trailing()
            }
            content()
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(v2 ? AnyShapeStyle(t.window.color) : AnyShapeStyle(LinearGradient(colors: [t.desk.top.color, t.desk.bottom.color], startPoint: .top, endPoint: .bottom)))
    }
}

/// Chip-style segmented control (control fill + separator border, 3 pt inset).
struct Segmented<T: Hashable>: View {
    @Environment(\.theme) private var t
    let options: [(T, String)]
    @Binding var selection: T
    var badge: (T) -> String? = { _ in nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button { withAnimation(Motion.fast) { selection = value } } label: {
                    HStack(spacing: 4) {
                        Text(label).ui(12.5, .medium).foregroundStyle(on ? t.text.color : t.text2.color)
                        if let b = badge(value) { Text(b).ui(12.5, .semibold).foregroundStyle(t.needsText.color) }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 11)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? t.surface.color : .clear)
                        .shadow(color: on ? .black.opacity(0.1) : .clear, radius: 1, y: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.control.color.opacity(t.isDark ? 1 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
    }
}

/// A white (surface) card with the card radius and shadow.
struct Card<Content: View>: View {
    @Environment(\.theme) private var t
    var needs = false
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(needs ? t.statusColor(.needsYou).color.opacity(0.55) : t.separator.color, lineWidth: 1))
            .shadow(color: Color.black.opacity(t.isDark ? 0.3 : 0.08), radius: 15, y: 10)
    }
}

/// A menu drawn as a field (card fill, 30 pt): borderless menus drop their label's background, so it goes outside.
struct FieldMenu<Items: View>: View {
    @Environment(\.theme) private var t
    let title: String
    var tint: RGB?
    var height: CGFloat = 30
    var expand = true
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu { items() } label: {
            Text(title + "  ▾").ui(13, tint == nil ? .regular : .medium).foregroundStyle((tint ?? t.text).color).lineLimit(1)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .fixedSize(horizontal: !expand, vertical: false)
        .padding(.horizontal, 10)
        .frame(maxWidth: expand ? .infinity : nil, minHeight: height, maxHeight: height, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill((tint?.opacity(0.12) ?? t.card).color))
        .accessibilityLabel(title)
    }
}
