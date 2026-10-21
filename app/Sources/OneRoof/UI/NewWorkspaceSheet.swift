import SwiftUI
import OneRoofCore

/// New Workspace Window (⇧⌘N, S00 §1.6): a name and a colour; opens a new main window for it.
struct NewWorkspaceSheet: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var name = ""
    @State private var colour: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace window").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
            Text("A workspace is a main window with its own sessions, layout and panel widths. Overview, Board and Decisions show every workspace.")
                .ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            TextField("Name, e.g. Website", text: $name)
                .textFieldStyle(.plain).ui(14)
                .padding(9).background(RoundedRectangle(cornerRadius: Radius.field).fill(t.control.color))
                .onSubmit(create)
            HStack(spacing: 7) {
                Text("Colour").ui(12).foregroundStyle(t.text.color)
                Button { colour = nil } label: { ColourSwatch(pastel: nil, selected: colour == nil, size: 20) }
                    .buttonStyle(.plain).accessibilityLabel("No colour").help("No colour")
                ForEach(Sticker.rowColors, id: \.name) { p in
                    Button { colour = p.name } label: { ColourSwatch(pastel: p, selected: colour == p.name, size: 20) }
                        .buttonStyle(.plain).accessibilityLabel(p.name).help(p.name.capitalized)
                }
            }
            HStack {
                Spacer()
                RoofButton("Cancel") { close() }.keyboardShortcut(.cancelAction)
                RoofButton("Create window", .primary) { create() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(t.window.color)
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        close()
        NotificationCenter.default.post(name: .newWorkspace, object: [n, colour ?? ""])
    }
}

extension Notification.Name {
    /// Create a workspace window (object: [name, colour]).
    static let newWorkspace = Notification.Name("oneroof.newWorkspace")
}
