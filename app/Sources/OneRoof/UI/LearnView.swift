import AppKit
import SwiftUI
import OneRoofCore

/// View › Learn (⌘⇧E): browse and play the agentic-engineering material inside One Roof — the field manual,
/// every skill's narrated page (its audio plays in place), One Roof's Help, and any extra Learn folders from Settings.
/// Everything is read where it lives; nothing is copied (owner D7).
struct LearnView: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var t: ThemeTokens { model.themes.centre.tokens }
    var items: [LearnItem] { model.learnItems }

    var current: LearnItem? { items.first { $0.id == (selected ?? model.learnTarget) } }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 0) {
            nav.frame(width: 300)
            Divider()
            if let c = current {
                VStack(spacing: 0) {
                    HStack {
                        Text(c.title).font(.system(size: 13, weight: .bold)).foregroundStyle(t.text.color)
                        Text(c.section).font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                        Spacer()
                        if c.audio { PlayPageButton(item: c, player: model.player) }
                        if !c.isFolder {
                            if c.section.lowercased().contains("skill") || c.path.contains("/skills/") {
                                // S11.U: send "/skill-name" to a live agent session.
                                let skill = ((c.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                                Menu("Use in a session") {
                                    ForEach(model.items.filter { $0.liveAgent != nil && $0.session.agent.isAgent }) { i in
                                        Button(i.session.name) { model.sendSkill(skill, to: i) }
                                    }
                                }
                                .controlSize(.small).fixedSize()
                            }
                            Button { NSWorkspace.shared.open(URL(fileURLWithPath: c.path)) } label: { Label("Open in browser", systemImage: "safari") }
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    Divider()
                    if c.isFolder { TrackList(item: c, player: model.player, tokens: t) }
                    else if c.path.hasSuffix(".md") { MarkdownPage(path: c.path) } else { WebPage(path: c.path, root: c.root, blocked: { LearnExclusions.isExcluded($0) }, pageScript: LearnExclusions.hideLinksScript) }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap").font(.system(size: 36)).foregroundStyle(t.secondaryText.color)
                    Text("Learn the agentic engineering process").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                    Text("Start with the course (press play to listen), or open any skill and send it to a running session.")
                        .font(.system(size: 12)).foregroundStyle(t.secondaryText.color).multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
            LearnPlayerBar(player: model.player, tokens: t) { selected = model.player.pageId; query = "" }
        }
        .background(t.background.color)
        .environment(\.colorScheme, model.themes.centre.colorScheme)
        .onAppear { model.loadLearn(); takeQuestion() }
        .onChange(of: model.learnQuery) { _, _ in takeQuestion() }
        .onChange(of: model.learnTarget) { _, t in if let t { selected = t; query = "" } }
        .onChange(of: model.learnItems.count) { _, _ in takeQuestion() }
    }

    /// A question from "How do I…" (menu, palette, plan panel): search for it and open the best page.
    private func takeQuestion() {
        guard let q = model.learnQuery else { return }
        query = q
        searchFocused = true
        guard !items.isEmpty else { return }          // the index is still loading; try again when it arrives
        model.learnQuery = nil
        if let best = model.learnMatches(q, limit: 1).first { selected = best.id }
    }

    private var nav: some View {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        // Best matches by meaning-ish word overlap first, then plain title matches not already listed.
        let best = q.isEmpty ? [] : model.learnMatches(q, limit: 10)
        let bestIds = Set(best.map(\.id))
        let rest = q.isEmpty ? items : items.filter { !bestIds.contains($0.id) && ($0.title + " " + $0.section).lowercased().contains(q) }
        let sections = Array(NSOrderedSet(array: rest.map(\.section))) as? [String] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Learn").font(.system(size: 17, weight: .bold)).foregroundStyle(t.text.color)
                Spacer()
                Button { model.learnMode = false } label: { Image(systemName: "terminal") }.buttonStyle(.borderless).help("Back to terminals")
            }
            TextField("How do I…? or search \(items.count) pages", text: $query).textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            List(selection: $selected) {
                if !best.isEmpty {
                    Section("Best matches") {
                        ForEach(best) { i in row(i, detail: true) }
                    }
                }
                ForEach(sections, id: \.self) { sec in
                    Section(sec) {
                        ForEach(rest.filter { $0.section == sec }) { i in row(i, detail: false) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .padding(12)
    }

    private func row(_ i: LearnItem, detail: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: i.audio ? "waveform" : i.path.hasSuffix(".md") ? "doc.text" : "book")
                .font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(i.title).font(.system(size: 12)).lineLimit(1)
                if detail { Text(i.section).font(.system(size: 10)).foregroundStyle(t.secondaryText.color).lineLimit(1) }
            }
        }
        .tag(i.id)
    }
}

struct LearnItem: Identifiable, Equatable {
    var id: String { path }
    var title: String
    var section: String
    var path: String
    var root: String
    var audio: Bool
    /// A few sentences to match questions against (skill description, or the start of the page's text).
    var summary: String = ""
    /// A page whose narration lives in a separate folder of clips (the course lessons).
    var audioFolder: String? = nil

    /// A folder of narration clips (an extra Learn folder), shown as a track list rather than a page.
    var isFolder: Bool { !path.hasSuffix(".html") && !path.hasSuffix(".md") }

    /// The page's audio in play order.
    func tracks() -> [CourseTrack] {
        guard audio else { return [] }
        if let f = audioFolder { return CourseAudio.tracks(folder: f) }
        return isFolder ? CourseAudio.tracks(folder: path) : CourseAudio.tracks(page: path)
    }
}

enum LearnIndex {
    static func build(agenticEngineering ae: String, extraFolders: [String] = [],
                      helpFolder: String? = AppResources.helpFolder) -> [LearnItem] {
        let fm = FileManager.default
        var out: [LearnItem] = []
        // The course (bundled package): course/NN-*.md, narration in course/audio/<lesson>/.
        let course = ae + "/course"
        for f in ((try? fm.contentsOfDirectory(atPath: course)) ?? []).sorted()
        where f.hasSuffix(".md") && f.first?.isNumber == true {
            let path = course + "/" + f
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let meta = Foundations.frontmatter(text)
            let base = (f as NSString).deletingPathExtension
            let clips = course + "/audio/" + base
            let audio = ((try? fm.contentsOfDirectory(atPath: clips)) ?? []).contains { $0.hasSuffix(".mp3") }
            out.append(LearnItem(title: meta["title"] ?? base, section: "Course", path: path, root: ae, audio: audio,
                                 summary: (meta["summary"] ?? "") + " " + String(MarkdownPage.body(text).prefix(1200)),
                                 audioFolder: audio ? clips : nil))
        }
        // LAB-768 · the Agentic Engineering deck bundled with the app (`<ae>/deck`): its home + track pages, then every
        // narrated card. A pack skill that also has a narrated card is shown once, as the card.
        let deck = AEFolder.deckRoot(ae)
        let manual = (deck ?? ae) + "/content/field-manual"
        let pages = ((try? fm.contentsOfDirectory(atPath: manual)) ?? []).filter { $0.hasSuffix(".html") }.sorted { a, b in
            a == "home.html" ? true : b == "home.html" ? false : a < b
        }
        for p in pages {
            let name = (p as NSString).deletingPathExtension
            out.append(LearnItem(title: name == "home" ? "Start here" : name.replacingOccurrences(of: "-", with: " ").capitalized,
                                 section: "Agentic Engineering", path: manual + "/" + p, root: deck ?? ae, audio: false,
                                 summary: plainText(manual + "/" + p)))
        }
        let cards = deck.map { AEFolder.deckCards($0) } ?? []
        let carded = Set(cards.map(\.slug))
        for c in cards where deck != ae {
            let text = (try? String(contentsOfFile: c.dir + "/SKILL.md", encoding: .utf8)) ?? ""
            let meta = Foundations.frontmatter(text)
            out.append(LearnItem(title: meta["name"] ?? c.slug, section: "Agentic Engineering · " + c.track, path: c.dir + "/" + c.slug + ".html",
                                 root: deck!, audio: fm.fileExists(atPath: c.dir + "/" + c.slug + "_audio"), summary: meta["description"] ?? ""))
        }
        for s in Foundations.skills(FoundationPaths(agenticEngineering: ae)) where deck == ae || !carded.contains((s.path as NSString).lastPathComponent) {
            let html = s.path + "/" + (s.path as NSString).lastPathComponent + ".html"
            guard fm.fileExists(atPath: html) else {
                // A plain skill (the bundled package): show its SKILL.md.
                out.append(LearnItem(title: s.name, section: "Skills · " + s.track, path: s.path + "/SKILL.md", root: ae,
                                     audio: false, summary: s.description))
                continue
            }
            let audio = fm.fileExists(atPath: s.path + "/" + (s.path as NSString).lastPathComponent + "_audio")
            out.append(LearnItem(title: s.name, section: "Skills · " + s.track, path: html, root: ae, audio: audio, summary: s.description))
        }
        // One Roof's own Help (bundled with the app).
        if let help = helpFolder {
            for f in ((try? fm.contentsOfDirectory(atPath: help)) ?? []).sorted() where f.hasSuffix(".md") {
                let path = help + "/" + f
                let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
                let base = (f as NSString).deletingPathExtension
                let fallback = base.drop { $0.isNumber || $0 == "_" }.replacingOccurrences(of: "-", with: " ").capitalized
                out.append(LearnItem(title: heading ?? fallback, section: "One Roof Help", path: path, root: help, audio: false,
                                     summary: String(MarkdownPage.body(text).prefix(1200))))
            }
        }
        // Extra Learn folders (Settings › Foundations): Markdown pages and narration folders, read in place.
        for folder in extraFolders {
            for e in LearnFolder.scan(folder) {
                out.append(LearnItem(title: e.title, section: e.section, path: e.path,
                                     root: e.narration ? e.path : (folder as NSString).expandingTildeInPath, audio: e.narration,
                                     summary: e.narration ? "\(e.clips.count) narrated parts: " + e.clips.map { CourseAudio.title(slugFile: $0) }.joined(separator: ". ")
                                         : plainText(e.path)))
            }
        }
        // LAB-713: pages that belong to another product (the Career Agent playbook).
        return out.filter { !LearnExclusions.isExcluded($0.path) }
    }

    /// The first ~1,500 characters of a page's text (tags, scripts and styles removed).
    static func plainText(_ path: String) -> String {
        guard let h = FileManager.default.contents(atPath: path).flatMap({ String(data: $0.prefix(40_000), encoding: .utf8) }) else { return "" }
        let noBlocks = h.replacingOccurrences(of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", with: " ", options: .regularExpression)
        let text = noBlocks.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(text.prefix(1500))
    }
}

/// "Play" / "Continue part n" for a page with narration.
private struct PlayPageButton: View {
    let item: LearnItem
    @ObservedObject var player: CoursePlayer
    var body: some View {
        let here = player.pageId == item.id
        let resume = player.saved(item.id)
        Button {
            if here { player.toggle() } else { player.play(pageId: item.id, title: item.title, tracks: item.tracks()) }
        } label: {
            Label(here ? (player.playing ? "Pause" : "Play") : resume.map { "Continue part \($0.track + 1)" } ?? "Play in One Roof",
                  systemImage: here && player.playing ? "pause.fill" : "play.fill")
        }
        .controlSize(.small)
        .help("Plays the narration here, at your speed, and keeps playing while you work")
    }
}

/// A narration folder's parts; click one to play from there.
private struct TrackList: View {
    let item: LearnItem
    @ObservedObject var player: CoursePlayer
    let tokens: ThemeTokens
    var body: some View {
        let tracks = item.tracks()
        List(Array(tracks.enumerated()), id: \.offset) { i, tr in
            Button { player.play(pageId: item.id, title: item.title, tracks: tracks, track: i) } label: {
                HStack {
                    Image(systemName: player.pageId == item.id && player.index == i ? "speaker.wave.2.fill" : "play.circle")
                        .foregroundStyle(tokens.accent.color)
                    Text("\(i + 1). \(tr.title)").font(.system(size: 13))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The player bar under Learn while something is loaded.
private struct LearnPlayerBar: View {
    @ObservedObject var player: CoursePlayer
    let tokens: ThemeTokens
    let openPage: () -> Void
    var body: some View {
        if player.pageId != nil {
            Divider()
            PlayerBar(player: player, tokens: tokens, onOpenPage: openPage)
        }
    }
}
