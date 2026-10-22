import AppKit
import OneRoofCore
import SwiftUI

/// LAB-523: the New session sheet's issue picker as a resizable panel beside the sheet (a popover cannot be resized).
/// A table with resizable columns (pick · order · key · title · state), state filters, and a reading pane under it that
/// shows the selected issue in full, so an issue can be read before it is added. The panel remembers its size.
/// The issues picked in a New session sheet, shared with its picker panel (two hosting views, one source of truth).
final class IssueSelection: ObservableObject {
    @Published var issues: [LinearIssue] = []
    /// "New bug…" and friends pressed in the panel: the sheet switches to that new-issue kind.
    @Published var newKind: WorkKind?

    /// Tick or untick; the first ticked stays first (the session's ticket).
    func toggle(_ i: LinearIssue) {
        if let n = issues.firstIndex(where: { $0.id == i.id }) { issues.remove(at: n) } else { issues.append(i) }
    }
}

enum IssuePickerPanel {
    private static weak var panel: NSPanel?

    static func show(parent: NSWindow?, theme: ThemeName, scale: Double, content: IssuePickerView) {
        if let p = panel { p.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: content.themed(theme, scale: scale))
        host.sizingOptions = []
        let p = NSPanel(contentViewController: host)
        p.styleMask = [.titled, .closable, .resizable, .utilityWindow]
        p.title = "Pick issues"
        p.isFloatingPanel = false
        p.becomesKeyOnlyIfNeeded = false
        p.appearance = theme.appearance
        p.minSize = NSSize(width: 520, height: 380)
        p.setContentSize(NSSize(width: 760, height: 620))
        if !SelfTest.isActive { p.setFrameAutosaveName("OneRoofIssuePicker") }
        if let parent, p.frameAutosaveName.isEmpty || !p.setFrameUsingName("OneRoofIssuePicker") {
            // Beside the sheet, on its right, where the old popover pointed.
            let f = parent.frame
            p.setFrameOrigin(NSPoint(x: f.maxX + 12, y: f.maxY - p.frame.height))
        }
        parent?.addChildWindow(p, ordered: .above)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    static func close() {
        guard let p = panel else { return }
        p.parent?.removeChildWindow(p)
        p.close()
        panel = nil
    }

    static var isOpen: Bool { panel?.isVisible ?? false }
}

struct IssuePickerView: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let workstreamId: String
    let title: String
    @ObservedObject var selection: IssueSelection
    let toggle: (LinearIssue) -> Void
    let newIssue: (WorkKind) -> Void
    let clear: () -> Void
    let done: () -> Void

    @State private var state: String?
    @State private var query = ""
    @State private var selected: LinearIssue.ID?

    private var open: [LinearIssue] {
        (model.issues[workstreamId] ?? []).filter { !["completed", "canceled"].contains($0.stateType) }.reversed()
    }
    private var pickedNow: [LinearIssue] { selection.issues }
    private var rows: [LinearIssue] { IssuePick.rows(open, picked: pickedNow.map(\.id), state: state, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chips
            VSplitView {
                table.frame(minHeight: 160)
                reader.frame(minHeight: 110)
            }
            footer
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 380)
        .background(t.card.color)
        .onAppear { if selected == nil { selected = pickedNow.first?.id ?? rows.first?.id } }
        // Nothing left picked while showing only the picked: back to All rather than an empty list.
        .onChange(of: pickedNow.isEmpty) { _, none in if none && state == IssuePick.pickedFilter { state = nil } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title).ui(13, .semibold).foregroundStyle(t.text.color)
            Spacer()
            TextField("", text: $query, prompt: Text("Filter by key, title or text"))
                .textFieldStyle(.plain).ui(12.5).padding(.horizontal, 8).frame(width: 240, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separator.color))
                .accessibilityLabel("Filter issues")
        }
    }

    /// All, then each state present with its count (filters reflect real states; there is always an All).
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(IssuePick.states(open, picked: pickedNow.count), id: \.label) { c in
                let on = state == c.state
                Button { state = c.state } label: {
                    Text("\(c.label) \(c.count)").ui(11.5, .medium).foregroundStyle(on ? t.onAccent.color : t.text.color)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(on ? t.accent.color : t.surface2.color))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
            Text(pickedNow.isEmpty ? "Tick one or more" : "\(pickedNow.count) picked").ui(11.5).foregroundStyle(t.text3.color)
        }
    }

    private var table: some View {
        let order = Dictionary(pickedNow.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a })
        return Table(rows, selection: $selected) {
            TableColumn("") { i in
                Toggle("", isOn: Binding(get: { order[i.id] != nil }, set: { _ in toggle(i) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .accessibilityLabel("Pick \(i.identifier)")
            }
            .width(22)
            TableColumn("#") { i in Text(order[i.id].map(String.init) ?? "").ui(11, .semibold, mono: true).foregroundStyle(t.text3.color) }
                .width(min: 18, ideal: 24, max: 40)
            TableColumn("Key") { i in Text(i.identifier).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color) }
                .width(min: 56, ideal: 74, max: 140)
            TableColumn("Title") { i in
                Text(i.shortTitle).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail).help(i.shortTitle)
            }
            .width(min: 160, ideal: 460)
            TableColumn("State") { i in Text(i.state).ui(11.5).foregroundStyle(t.text2.color) }
                .width(min: 60, ideal: 90, max: 160)
        }
        .contextMenu(forSelectionType: LinearIssue.ID.self) { _ in EmptyView() } primaryAction: { ids in
            // Double-click (or Return) ticks or unticks the row.
            for id in ids { if let i = open.first(where: { $0.id == id }) { toggle(i) } }
        }
        .scrollContentBackground(.hidden)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface.color))
    }

    /// The selected issue in full: title, state, link and description.
    @ViewBuilder private var reader: some View {
        let issue = open.first { $0.id == selected }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let i = issue {
                    HStack(spacing: 8) {
                        Text(i.identifier).ui(12, .semibold, mono: true).foregroundStyle(t.text.color)
                        Text(i.state).ui(11).foregroundStyle(t.text2.color)
                        if let m = i.milestone { Text("· " + m).ui(11).foregroundStyle(t.text3.color) }
                        Spacer()
                        if let u = URL(string: i.url), !i.url.isEmpty { Link(destination: u) { Text("Linear ↗").ui(11.5).foregroundStyle(t.text3.color) } }
                        Button(order(of: i) == nil ? "Add to session" : "Remove") { toggle(i) }
                            .controlSize(.small)
                    }
                    Text(i.shortTitle).ui(14, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Text(describe(i)).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Select an issue to read it in full before adding it.").ui(12).foregroundStyle(t.text2.color)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface.color))
    }

    private func order(of i: LinearIssue) -> Int? { pickedNow.firstIndex { $0.id == i.id }.map { $0 + 1 } }

    private func describe(_ i: LinearIssue) -> AttributedString {
        let body = i.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return AttributedString("No description.") }
        return (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("New").ui(11.5).foregroundStyle(t.text3.color)
            ForEach([WorkKind.deliverable, .defect, .chore, .spike, .decision], id: \.self) { k in
                Button((k.labelNames.first ?? k.rawValue).lowercased()) { newIssue(k) }.buttonStyle(.link).ui(11.5)
            }
            Spacer()
            if !pickedNow.isEmpty { Button("Clear") { clear() }.buttonStyle(.plain).ui(11.5).foregroundStyle(t.text2.color) }
            Button("Done") { done() }.keyboardShortcut(.defaultAction)
        }
    }
}
