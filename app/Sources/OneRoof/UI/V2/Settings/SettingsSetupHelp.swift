import SwiftUI
import OneRoofCore

/// A13 Settings · A14 Foundations issue + Setup · A15 Help. All built on PanelView; fill rows from real data
/// (Foundations checks, seat usage, settings.learnFolders, docs/help pages).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", seats = "Seats & accounts", notifications = "Notifications", onDevice = "On-device model", foundations = "Foundations", learn = "Learn", shortcuts = "Shortcuts", updates = "Updates"
    var id: String { rawValue }
}

struct SettingsV2: View {
    var tokens: V2Planes
    @Binding var look: Look
    @State var pane: SettingsPane = .general
    var panes: (SettingsPane) -> [PanelSpec.V2Block]   // supplied by V2Adapters from AppModel
    var body: some View {
        if pane == .appearance { HStack(alignment: .top) { nav; LooksPicker(look: $look, onCustomize: {}) } }
        else { PanelView(spec: .init(kicker: "SETTINGS", title: pane.rawValue, columns: pane == .shortcuts ? 2 : 1, leading: navBlock, blocks: panes(pane)), tokens: tokens) }
    }
    private var nav: some View { List(SettingsPane.allCases, selection: $pane) { Text($0.rawValue).tag($0) }.frame(width: 220) }
    private var navBlock: PanelSpec.V2Block { .init(title: "SETTINGS", rows: SettingsPane.allCases.map { p in .init(title: p.rawValue, selected: p == pane, run: { pane = p }) }) }
}

struct FoundationsIssueSheet: View {
    var headline: String; var why: String; var repos: [String]; var whatFixDoes: String; var command: String; var tokens: V2Planes
    var onFix: (String?) -> Void
    var body: some View {
        PanelView(spec: .init(kicker: "FOUNDATIONS · \(repos.count) ISSUE", title: headline, subtitle: why,
            actions: [.init(title: "Fix all \(repos.count)", primary: true, run: { onFix(nil) })], columns: 2,
            blocks: [.init(title: "MISSING", rows: repos.map { r in .init(lead: .issue, title: r, action: "Fix", run: { onFix(r) }) }),
                     .init(title: "WHAT FIX DOES", text: [whatFixDoes]), .init(title: "THE COMMAND", text: [command], mono: true)]), tokens: tokens)
    }
}

struct SetupFlow: View {
    var tokens: V2Planes; var found: [PanelSpec.V2Row]; var onFinish: () -> Void
    @State private var step = 1
    var body: some View {
        Group {
            switch step {
            case 1: PanelView(spec: .init(kicker: "STEP 1 OF 4 · AGENTS", title: "Here\u{2019}s who One Roof found on this Mac", actions: [.init(title: "Continue", primary: true, run: { step = 2 })], blocks: [.init(title: "FOUND", rows: found)]), tokens: tokens)
            case 2: PanelView(spec: .init(kicker: "STEP 2 OF 4 · WORKSPACE", title: "One launch folder, one memory, one set of rules", actions: [.init(title: "Back", run: { step = 1 }), .init(title: "Continue", primary: true, run: { step = 3 })], columns: 2, blocks: [.init(title: "LAUNCH FOLDER"), .init(title: "RULES")]), tokens: tokens)
            default: PanelView(spec: .init(kicker: "STEPS 3–4 · KIT AND LOOK", title: "Install the kit, then pick a look", actions: [.init(title: "Back", run: { step = 2 }), .init(title: "Open One Roof", primary: true, run: onFinish)], columns: 2, blocks: [.init(title: "THE KIT"), .init(title: "LOOK")]), tokens: tokens)
            }
        }.frame(minWidth: 900, minHeight: 600)
    }
}

struct HelpV2: View {
    var pages: [LearnItem]   // LearnIndex section "One Roof Help"
    @State private var selected: String?
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            List(pages, selection: $selected) { Text($0.title).tag($0.id) }.frame(width: 240)
            if let p = pages.first(where: { $0.id == (selected ?? pages.first?.id) }) { MarkdownPage(path: p.path).padding(24) }
        }
    }
}
