import AppKit
import SwiftUI
import OneRoofCore

// LAB-2332 · the places that are coming (Agents, Factory, Train, Ship): one page that says what the place is for,
// what will live there, where the nearest thing is today, and its tickets. The words are `PlannedPlaceCopy`.
// Factory also shows the recipe library (LAB-2330 first cut, recipes from LAB-2329); running one waits for LAB-198.

struct PlannedPlacePage: View {
    @Environment(\.theme) private var t
    let place: Place
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    weak var controller: MainWindowController?

    private var copy: PlannedPlaceCopy? { PlannedPlaceCopy.of(place) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(place.title).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).accessibilityAddTraits(.isHeader)
                    PlannedTag()
                    Spacer()
                }
                if let copy {
                    Text(copy.oneLine).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    section("Coming") {
                        ForEach(copy.coming, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("▸").foregroundStyle(t.text3.color)
                                Text(line).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    section("Today, use") {
                        HStack(spacing: 8) {
                            ForEach(Array(copy.today.enumerated()), id: \.offset) { _, item in
                                if let action = action(item.link) { RoofButton(item.label, .secondary, action: action).fixedSize() }
                            }
                        }
                    }
                    section("Tickets") {
                        HStack(spacing: 8) {
                            ForEach(copy.tickets, id: \.self) { id in TicketButton(id: id, model: model) }
                        }
                    }
                }
                if place == .factory { FactoryLibrary() }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(t.window.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(place.title), planned")
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(title)
            content()
        }
    }

    private func action(_ link: PlannedPlaceCopy.Link) -> (() -> Void)? {
        switch link {
        case .place(let p): return { [weak controller] in controller?.v2Open(p) }
        case .settings(let pane, _): return { [weak controller] in controller?.v2OpenSettings(tab: pane) }
        case .doc(_, let path):
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }   // only on a Mac that has the doc
            return { NSWorkspace.shared.open(url) }
        }
    }
}

/// A roadmap ticket: a button to its Linear page when Linear is connected (Projects), else the id as text.
struct TicketButton: View {
    @Environment(\.theme) private var t
    let id: String
    @ObservedObject var model: AppModel

    var body: some View {
        if let u = PlannedPlaceCopy.ticketURL(id, workspace: PlannedPlaceCopy.workspace(fromLinearURLs: model.workstreams.map(\.url))) {
            RoofButton(id, .secondary) { NSWorkspace.shared.open(u) }.fixedSize().help("Open \(id) in Linear")
        } else {
            Text(id).ui(12, .semibold).foregroundStyle(t.text2.color).textSelection(.enabled)
                .help("A One Roof roadmap ticket; connect Linear in Projects to open it")
        }
    }
}

/// The PLANNED tag, as Evals' DRAFT tag but grey: the place is not there yet.
struct PlannedTag: View {
    @Environment(\.theme) private var t
    var body: some View {
        Text(PlannedPlaceCopy.tag.uppercased()).ui(10, .bold).foregroundStyle(t.onAccent.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(t.text3.color))
            .help("Coming in a later release; the tickets below say what and when")
    }
}

/// LAB-2330 first cut · the Factory's recipe library: the built-in recipes and your own files, each with its roles,
/// pattern, finish line and budget. Run waits for the orchestrator (LAB-198).
struct FactoryLibrary: View {
    @Environment(\.theme) private var t
    @State private var loaded = AgentRecipes.load()
    @State private var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel("Recipes · \(loaded.recipes.count)")
                Spacer()
                RoofButton("Recipes folder", .secondary) {
                    try? FileManager.default.createDirectory(at: AgentRecipes.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AgentRecipes.folder)
                }.fixedSize().help("Your own recipes: one JSON file each, in the shape of a built-in (Copy as JSON)")
                RoofButton("Reload", .secondary) { loaded = AgentRecipes.load() }.fixedSize()
            }
            ForEach(loaded.recipes) { r in recipe(r) }
            ForEach(loaded.skipped, id: \.self) { s in
                Text("Skipped " + s).ui(12).foregroundStyle(t.needsText.color)
            }
        }
        .padding(.top, 6)
    }

    private func recipe(_ r: AgentRecipe) -> some View {
        let expanded = open == r.id
        return VStack(alignment: .leading, spacing: 8) {
            Button { open = expanded ? nil : r.id } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.text3.color)
                    Text(r.name).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text(r.builtIn ? "built in" : "yours").ui(11).foregroundStyle(t.text3.color)
                    Spacer()
                    Text(r.line).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.name), \(r.line)\(expanded ? ", open" : "")")
            if expanded {
                Text(r.summary).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Text(r.pattern.steps).ui(12).foregroundStyle(t.text2.color)
                ForEach(r.roles, id: \.name) { role in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(role.name).ui(12, .semibold).foregroundStyle(t.text.color).frame(width: 70, alignment: .leading)
                        Text(role.agent.displayName + (role.model.map { " · " + $0 } ?? "")).ui(12).foregroundStyle(t.accentText.color).frame(width: 110, alignment: .leading)
                        Text(role.does).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Finish line: `\(r.finishLine.check)` passes → \(Self.result(r.finishLine.result))").ui(12).foregroundStyle(t.text2.color)
                let problems = r.problems
                if !problems.isEmpty {
                    Text("Cannot run: " + problems.joined(separator: "; ")).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    RoofButton("Run on a task", .primary) {}.fixedSize().disabled(true)
                        .help("Running a recipe needs the orchestrator (LAB-198); the Factory shows the library until then")
                    RoofButton("Copy as JSON", .secondary) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AgentRecipes.json(r), forType: .string)
                    }.fixedSize()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(t.border.color, lineWidth: 1))
    }

    static func result(_ r: String) -> String {
        switch r { case "qa": return "the ticket moves to QA with the evidence"; case "pr": return "a pull request"; default: return "a report" }
    }
}

// MARK: Trace

/// LAB-2332 · Trace: every agent action. History (today's page, unchanged) is its first tab; X-ray and Cost move in
/// later (LAB-2326).
struct V2TracePage: View {
    @Environment(\.theme) private var t
    let model: AppModel   // LAB-2105: not observed (the model publishes every second); History listens for its own changes
    @ObservedObject var win: WindowState

    enum Tab: String, CaseIterable { case history = "History", xray = "X-ray", cost = "Cost" }
    @State private var tab: Tab = .history

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tb in
                    Button { tab = tb } label: {
                        HStack(spacing: 4) {
                            Text(tb.rawValue).ui(12.5, tab == tb ? .semibold : .regular)
                            if tb != .history { Text(PlannedPlaceCopy.tag.uppercased()).ui(7, .bold).foregroundStyle(t.text3.color) }
                        }
                        .foregroundStyle(tab == tb ? t.text.color : t.text2.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tab == tb ? t.surface.color : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tb.rawValue + (tb != .history ? ", planned" : "") + (tab == tb ? ", selected" : ""))
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 6)
            .overlay(alignment: .bottom) { Hairline() }
            switch tab {
            case .history: V2HistoryPage(model: model, win: win)
            case .xray: tracePlanned("X-ray: each agent's tool calls, files and subagents, step by step, for any session or loop round.")
            case .cost: tracePlanned("Cost per run: what each session, loop round and recipe run cost, by agent and account.")
            }
        }
        .background(t.window.color)
    }

    private func tracePlanned(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PlannedTag()
            Text(line).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            TicketButton(id: "LAB-2326", model: model)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
