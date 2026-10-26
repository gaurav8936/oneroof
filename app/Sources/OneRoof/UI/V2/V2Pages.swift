import AppKit
import SwiftUI
import OneRoofCore

/// The page over the current place (LAB-1084): Settings (B1.x), Help (B4.1) or Release notes (B4.2). The rail keeps
/// the place you came from; ‹ back, ⌘[, Esc or any place closes it.
struct V2PageHost: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController

    var body: some View {
        Group {
            switch controller.v2Page {
            case "Settings": V2SettingsPage(model: model, controller: controller)
            case "Help": V2HelpPage(model: model, controller: controller)
            case "Release notes": V2ReleaseNotesPage(model: model, controller: controller)
            case "All windows": V2WallPage(model: model, win: win, controller: controller)
            default: Color.clear
            }
        }
        .themed(model.themes.centre, scale: win.textScale)
        .environment(\.v2Window, true)
    }
}

/// Page frame: breadcrumb, title, subtitle, a trailing control, then content; flat on the centre colour.
struct V2PageFrame<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var t
    let crumb: String
    let title: String
    let subtitle: String
    let close: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Button(action: close) { Text("‹ Back").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).help("Back to where you were (⌘[ or Esc)")   // the window's key monitor owns ⌘[ / Esc
                        Text(crumb.uppercased()).ui(10.5, .bold).tracking(0.5).foregroundStyle(t.accentText.color)
                    }
                    Text(title).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                    Text(subtitle).ui(13).foregroundStyle(t.text2.color).lineLimit(2)
                }
                Spacer()
                trailing()
            }
            content()
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
    }
}

/// Settings (B1.1-B1.6): the nine panes down the left, the chosen pane on the right — today's settings, every one.
struct V2SettingsPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var controller: MainWindowController

    static let subtitles = ["Where sessions start, what runs at startup and in the background, and how new sessions start.",
                            "One look sets every panel at once.", "Each agent's default account, model and arguments.",
                            "What is worth a banner, and whether macOS lets One Roof show them.",
                            "Optional local captions; nothing leaves this Mac.", "The folders One Roof reads: projects, shared rules, the kit, memory.",
                            "The bundled deck and your own Learn folders.", "Every menu shortcut, and the global hotkey.",
                            "Which build you run, and how new ones arrive."]

    var body: some View {
        let pane = min(max(controller.v2SettingsPane, 0), SettingsView.v2Panes.count - 1)
        V2PageFrame(crumb: "Settings", title: SettingsView.v2Panes[pane], subtitle: Self.subtitles[pane], close: { controller.v2Page = nil }) {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 14) {
                Card(padding: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel("Settings").padding(.horizontal, 8).padding(.vertical, 6)
                        ForEach(Array(SettingsView.v2Panes.enumerated()), id: \.offset) { i, name in
                            Button { controller.v2SettingsPane = i } label: {
                                Text(name).ui(12.5, i == pane ? .semibold : .regular).foregroundStyle(t.text.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(i == pane ? t.selection.color : .clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(i == pane ? .isSelected : [])
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: 210)
                Card(padding: 0) {
                    SettingsView(model: model, v2Pane: pane).id(pane)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

/// Help (B4.1): getting started and the help pages. 1.9.2 (LAB-1274): this is One Roof Help's only home in the v2 window
/// (Learn has no Pages list); a link to a help page from Learn or Search opens it here (`AppModel.helpTarget`).
struct V2HelpPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var controller: MainWindowController
    @State private var page: String? = AppResources.helpStartPage()

    private var pages: [String] {
        guard let f = AppResources.helpFolder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: f)) ?? []).filter { $0.hasSuffix(".md") }.sorted().map { f + "/" + $0 }
    }

    static func title(_ path: String) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let words = name.drop { $0.isNumber || $0 == "_" }.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    var body: some View {
        let list = pages
        V2PageFrame(crumb: "Help", title: page.map(Self.title) ?? "Help", subtitle: "One Roof runs every coding agent in one place, each saying in plain words what it's doing and what it needs from you.",
                    close: { controller.v2Page = nil }) {
            if let page { RoofButton("Open the file") { controller.v2Page = nil; model.openInViewer(page) } }
        } content: {
            if list.isEmpty {
                Text("One Roof Help is not bundled with this build.").ui(13).foregroundStyle(t.text2.color)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Card(padding: 18) {
                        ScrollView { if let page { MarkdownPage(path: page).frame(maxWidth: .infinity, alignment: .leading) } }
                    }
                    Card(padding: 8) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                MicroLabel("In this help").padding(.horizontal, 8).padding(.vertical, 6)
                                ForEach(list, id: \.self) { p in
                                    Button { page = p } label: {
                                        Text(Self.title(p)).ui(12.5, p == page ? .semibold : .regular).foregroundStyle(t.text.color)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p == page ? t.selection.color : .clear))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 240)
                }
            }
        }
        .onAppear { takeTarget() }
        .onChange(of: model.helpTarget) { _, _ in takeTarget() }
    }

    /// A help page asked for from Learn or Search (LAB-1274).
    private func takeTarget() {
        guard let target = model.helpTarget else { return }
        model.helpTarget = nil
        if FileManager.default.fileExists(atPath: target) { page = target }
    }
}

/// Release notes (B4.2): the bundled notes, one card per release, newest first.
struct V2ReleaseNotesPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var controller: MainWindowController

    struct Release: Identifiable { var id: String { heading }; var heading: String; var bullets: [String] }

    /// "## 1.4.1 — title (date)" headings and their "- " bullets (continuation lines joined); other text is dropped.
    static func parse(_ text: String) -> [Release] {
        var out: [Release] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { out.append(Release(heading: String(line.dropFirst(3)), bullets: [])); continue }
            guard !out.isEmpty else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") { out[out.count - 1].bullets.append(String(line.dropFirst(2))) }
            else if !trimmed.isEmpty, line.hasPrefix(" "), !out[out.count - 1].bullets.isEmpty { out[out.count - 1].bullets[out[out.count - 1].bullets.count - 1] += " " + trimmed }
        }
        return out
    }

    var body: some View {
        let path = AppResources.releaseNotes
        let releases = Self.parse(path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? "")
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        V2PageFrame(crumb: "Release notes", title: "One Roof \(v)", subtitle: releases.first?.heading ?? "", close: { controller.v2Page = nil }) {
            if let path { RoofButton("Open the file") { controller.v2Page = nil; model.openInViewer(path) } }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if releases.isEmpty { Text("Release notes are not bundled with this build.").ui(13).foregroundStyle(t.text2.color) }
                    ForEach(Array(releases.prefix(40).enumerated()), id: \.offset) { i, r in
                        Card(padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                MicroLabel(i == 0 ? "In this release · " + r.heading : r.heading)
                                ForEach(Array(r.bullets.enumerated()), id: \.offset) { _, b in
                                    Text((try? AttributedString(markdown: b)) ?? AttributedString(b)).ui(12.5).foregroundStyle(t.text.color)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

/// The page layer's host: takes the keyboard while a page shows, so keys never reach the terminal hidden under it.
final class V2PageHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { !isHidden }
}
