import AppKit
import SwiftUI
import OneRoofCore

/// Settings › Appearance in the v2 window (handover A10.3): one look sets every panel at once — six looks as preview
/// cards — then Customize each panel… (today's per-panel grid, kept whole), text size 85–130 % (⌘+ ⌘− ⌘0), Follow
/// macOS light and dark, Fill rows with their colour, Sticker style Bold / Soft and the window's colour.
struct V2LooksPicker<Customize: View>: View {
    @ObservedObject var model: AppModel
    var customize: () -> Customize
    @State private var customizing: Bool

    /// Customize starts open when the panels are already a custom mix.
    init(model: AppModel, @ViewBuilder customize: @escaping () -> Customize) {
        self.model = model; self.customize = customize
        _customizing = State(initialValue: Look.matching(model.chosenThemes) == nil)
    }

    private var current: Look? { Look.matching(model.chosenThemes) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("One look sets every panel at once").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(customizing ? "Done customizing" : "Customize each panel…") { customizing.toggle() }
                            .buttonStyle(.link)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(Look.allCases) { look in card(look) }
                    }
                    if current == nil {
                        Text("Your own mix of panel themes (Customize). Pick a look to set them all again.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if customizing {
                Section("Each panel") {
                    customize()
                    Text("Blueprint stays available for the terminal in View › Terminal Theme.").font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Text size") {
                HStack {
                    Slider(value: Binding(get: { model.active.textScale }, set: { model.active.setTextScale($0) }), in: 0.85...1.3, step: 0.05)
                        .frame(width: 200)
                    Text("\(Int(model.active.textScale * 100))%").monospacedDigit()
                    Text("85–130 % · ⌘+ ⌘− ⌘0").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Follow macOS light and dark", isOn: $model.settings.followSystemAppearance)
            Text("In Dark Mode, Daylight and pastel panels turn Midnight; the look you picked stays as it is.").font(.caption).foregroundStyle(.secondary)
            Toggle("Fill rows with their colour", isOn: $model.settings.tintRows)
            Text("A row picks its colour from Stickers and Colour… (right-click a row).").font(.caption).foregroundStyle(.secondary)
            Picker("Sticker style", selection: $model.settings.stickerStyle) {
                Text("Bold").tag("bold")
                Text("Soft").tag("soft")
            }
            .pickerStyle(.segmented)
            LabeledContent("Window colour") { V2WindowColourPicker(win: model.active) }
        }
        .formStyle(.grouped)
    }

    private func card(_ look: Look) -> some View {
        let on = current == look
        let p = look.panelThemes
        return Button {
            model.chosenThemes = look.panelThemes   // AppModel keeps settings.lookName in step
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    p.sidebar.tokens.control.color.frame(width: 34)
                    ZStack {
                        p.centre.tokens.window.color
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(p.terminal.tokens.terminal.background.color).padding(6)
                    }
                    p.plan.tokens.window.color.frame(width: 26)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: on ? 2 : 1))
                Text(look.title).font(.system(size: 12, weight: .semibold))
                Text(look.blurb).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(look.blurb)
        .accessibilityLabel(look.title + (on ? ", selected" : ""))
    }
}

/// The window's colour (LAB-590): none or one of the row colours.
struct V2WindowColourPicker: View {
    @ObservedObject var win: WindowState
    var body: some View {
        Menu {
            Button("None") { win.setColour(nil) }
            ForEach(Sticker.rowColors, id: \.name) { c in
                Button(c.name.capitalized) { win.setColour(c.name) }
            }
        } label: {
            Text(win.colour?.capitalized ?? "None")
        }
        .fixedSize()
    }
}
