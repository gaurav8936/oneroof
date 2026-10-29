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
    /// LAB-1559: the filter takes the keyboard when the picker opens, so typing searches straight away.
    @FocusState private var filterFocused: Bool
    @State private var selected: LinearIssue.ID?
    /// LAB-547: the clicked column (none = the default order), kept for the next time the panel opens.
    @State private var sortOrder: [KeyPathComparator<LinearIssue>] = IssuePickerView.lastSort
    static var lastSort: [KeyPathComparator<LinearIssue>] = []

    private var open: [LinearIssue] {
        (model.issues[workstreamId] ?? []).filter {
            !["completed", "canceled"].contains($0.stateType) && (!activeOnly || ActiveFilter.issue($0.stateType) || selection.issues.contains($0))
        }.reversed()
    }
    /// LAB-1571: In Progress and In Review only, until switched off (remembered; off by default: new work is in Backlog).
    @AppStorage("newSession.issuesActiveOnly") private var activeOnly = false
    private var pickedNow: [LinearIssue] { selection.issues }
    private var rows: [LinearIssue] {
        // LAB-533: the "Not ready" chip shows every open issue below the quality bar.
        if state == IssueQuality.notReadyFilter {
            let all = IssuePick.rows(open, picked: pickedNow.map(\.id), state: nil, query: query)
            return IssuePick.sorted(all.filter { !IssueQuality.assess($0).ready }, by: sortOrder)
        }
        return IssuePick.sorted(IssuePick.rows(open, picked: pickedNow.map(\.id), state: state, query: query), by: sortOrder)
    }
    private var notReadyCount: Int { open.filter { !IssueQuality.assess($0).ready }.count }
    private var loading: Bool { model.issuesLoading.contains(workstreamId) }

    /// LAB-546: fetch again from Linear, so issues created after the window (or session) opened show up.
    private func refresh(force: Bool = false) { model.loadIssues(projectId: workstreamId, force: force, maxAge: 10) }

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
        .onAppear {
            if selected == nil { selected = pickedNow.first?.id ?? rows.first?.id }
            refresh(force: true)
        }
        // While the panel is open, every 60 s too.
        .task(id: workstreamId) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { refresh() }
            }
        }
        .onChange(of: sortOrder) { _, v in Self.lastSort = v }
        // Nothing left picked while showing only the picked: back to All rather than an empty list.
        .onChange(of: pickedNow.isEmpty) { _, none in if none && state == IssuePick.pickedFilter { state = nil } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
            Button { refresh(force: true) } label: {
                Group {
                    if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise").ui(12, .medium) }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless).disabled(loading || workstreamId.isEmpty)
            .help("Refresh from Linear (also on opening, on every filter click and every minute)")
            .accessibilityLabel(loading ? "Refreshing issues" : "Refresh issues from Linear")
            Spacer()
            Toggle("Active only", isOn: $activeOnly).toggleStyle(.checkbox).ui(12)
                .help("Only issues In Progress or In Review")
            TextField("", text: $query, prompt: Text("Filter by key, title or text"))
                .textFieldStyle(.plain).ui(12.5).padding(.horizontal, 8).frame(width: 240, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separator.color))
                .accessibilityLabel("Filter issues")
                .focused($filterFocused)
                .onAppear { DispatchQueue.main.async { filterFocused = true } }
        }
    }

    /// All, then each state present with its count (filters reflect real states; there is always an All).
    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(IssuePick.states(open, picked: pickedNow.count), id: \.label) { c in
                let on = state == c.state
                Button { state = c.state; refresh() } label: {
                    Text("\(c.label) \(c.count)").ui(11.5, .medium).foregroundStyle(on ? t.onAccent.color : t.text.color)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(on ? t.accent.color : t.surface2.color))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
            if notReadyCount > 0 {
                let on = state == IssueQuality.notReadyFilter
                Button { state = on ? nil : IssueQuality.notReadyFilter } label: {
                    Text("Not ready \(notReadyCount)").ui(11.5, .medium).foregroundStyle(on ? t.onAccent.color : t.needsText.color)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(on ? t.accent.color : t.surface2.color))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                .help("Issues missing something the quality bar asks for (One Roof Help › Issue quality bar)")
            }
            Spacer()
            if !sortOrder.isEmpty {
                Button("Default order") { sortOrder = [] }.buttonStyle(.link).ui(11.5)
                    .help("Back to In Progress, To do, Backlog, then In Review")
            }
            Text(pickedNow.isEmpty ? "Tick one or more" : "\(pickedNow.count) picked").ui(11.5).foregroundStyle(t.text3.color)
        }
    }

    private var table: some View {
        let order = Dictionary(pickedNow.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a })
        return Table(rows, selection: $selected, sortOrder: $sortOrder) {
            TableColumn("") { i in
                Toggle("", isOn: Binding(get: { order[i.id] != nil }, set: { _ in toggle(i) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .accessibilityLabel("Pick \(i.identifier)")
            }
            .width(22)
            TableColumn("#") { i in Text(order[i.id].map(String.init) ?? "").ui(11, .semibold, mono: true).foregroundStyle(t.text3.color) }
                .width(min: 18, ideal: 24, max: 40)
            TableColumn("Key", value: \.number) { i in Text(i.identifier).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color) }
                .width(min: 56, ideal: 74, max: 140)
            TableColumn("Title", value: \.shortTitle) { i in
                HStack(spacing: 6) {
                    Text(i.shortTitle).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail).help(i.shortTitle)
                    Spacer(minLength: 0)
                    NotReadyBadge(report: IssueQuality.assess(i))
                }
            }
            .width(min: 160, ideal: 400)
            TableColumn("State", value: \.pickRank) { i in Text(i.state).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1) }
                .width(min: 60, ideal: 90, max: 160)
            TableColumn("Created", value: \.created) { i in dateText(i.createdAt) }
                .width(min: 54, ideal: 70, max: 120)
            TableColumn("Updated", value: \.updated) { i in dateText(i.updatedAt) }
                .width(min: 54, ideal: 70, max: 120)
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
                    let q = IssueQuality.assess(i)
                    if !q.ready {
                        Text(q.missingLine).ui(11.5, .medium).foregroundStyle(t.needsText.color)
                            .fixedSize(horizontal: false, vertical: true).help(q.tooltip)
                    }
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

    /// "16:05" today, "21 Oct" this year, "21 Oct 2025" before; the full date and time on hover.
    private func dateText(_ d: Date?) -> some View {
        let s: String
        if let d {
            let cal = Calendar.current
            if cal.isDateInToday(d) { s = d.formatted(date: .omitted, time: .shortened) }
            else if cal.isDate(d, equalTo: Date(), toGranularity: .year) { s = d.formatted(.dateTime.day().month(.abbreviated)) }
            else { s = d.formatted(.dateTime.day().month(.abbreviated).year()) }
        } else { s = "" }
        return Text(s).ui(11.5).monospacedDigit().foregroundStyle(t.text2.color).lineLimit(1)
            .help(d?.formatted(date: .complete, time: .shortened) ?? "")
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

/// LAB-533: "not ready" on an issue below the quality bar; the tooltip lists what is missing.
struct NotReadyBadge: View {
    @Environment(\.theme) private var t
    let report: IssueQuality.Report

    var body: some View {
        if !report.ready {
            Text("not ready").ui(10, .semibold).foregroundStyle(t.needsText.color).lineLimit(1).fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(t.surface2.color))
                .overlay(Capsule().strokeBorder(t.separator.color))
                .help(report.tooltip)
                .accessibilityLabel("Not ready. " + report.missingLine)
        }
    }
}
