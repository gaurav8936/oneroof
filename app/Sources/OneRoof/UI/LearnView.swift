import AppKit
import SwiftUI
import OneRoofCore

/// View › Learn (⌘⇧E). The classic window (settings.ui2 off) lists pages: the field manual, every skill's narrated page
/// (its audio plays in place), One Roof's Help, and any extra Learn folders from Settings. The v2 window is three views,
/// Radio · Writing · All cards (1.9.2, LAB-1274: no Pages list and no course). Read where it lives; nothing is copied (D7).
struct LearnView: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var t: ThemeTokens { model.themes.centre.tokens }
    var items: [LearnItem] { model.learnItems }

    var current: LearnItem? { items.first { $0.id == (selected ?? model.learnTarget) } }

    /// v2 (LAB-1233, LAB-1274): where Learn is (Radio, a band, a card, Writing, a post, a programme, All cards), the deck
    /// and the posts. Classic (settings.ui2 off) shows pagesBody only, as before.
    @StateObject private var lnav = LearnNav()
    @State private var deck: LearnDeck?
    @State private var posts: [LearnPost] = []
    @State private var appeared = false
    /// LAB-1251: the owner's posts come from the blog hub (BlogHub, cached), plus any in Learn folders.
    @ObservedObject private var blog = LearnBlogFeed.shared

    /// LAB-1835 · the shared Agentic Engineering page (default from 1.9.32) and its bridge; LAB-1837: Settings › Learn › classic
    /// screens (or a build without the saved page) shows the native v2 screens below instead.
    @StateObject private var shared = LearnSharedController()
    @State private var sharedAppeared = false
    @Environment(\.textScale) private var textScale

    var body: some View {
        if model.settings.ui2 {
            if model.learnUsesShared, let loc = model.learnShared { sharedBody(loc) } else { v2Body }
        } else { pagesBody }
    }

    private var pagesBody: some View {
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
                    Text("Open any skill to hear it (press play), or send it to a running session.")
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

    /// A folder of narration clips (an extra Learn folder), shown as a track list rather than a page.
    var isFolder: Bool { !path.hasSuffix(".html") && !path.hasSuffix(".md") }

    /// The page's audio in play order.
    func tracks() -> [CourseTrack] {
        guard audio else { return [] }
        return isFolder ? CourseAudio.tracks(folder: path) : CourseAudio.tracks(page: path)
    }
}

enum LearnIndex {
    static func build(agenticEngineering ae: String, extraFolders: [String] = [],
                      helpFolder: String? = AppResources.helpFolder) -> [LearnItem] {
        let fm = FileManager.default
        var out: [LearnItem] = []
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
        let button = Button {
            if here { player.toggle() } else { player.play(pageId: item.id, title: item.title, tracks: item.tracks()) }
        } label: {
            Label(here ? (player.playing ? "Pause" : "Play") : resume.map { "Continue part \($0.track + 1)" } ?? "Play in One Roof",
                  systemImage: here && player.playing ? "pause.fill" : "play.fill")
        }
        .help("Plays the narration here, at your speed, and keeps playing while you work")
        button.controlSize(.small)
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
    /// LAB-1629 · the v2 window's ⏮ ⏭ and back to band.
    var onPrevCard: (() -> Void)? = nil
    var onNextCard: (() -> Void)? = nil
    var onBand: (() -> Void)? = nil
    var body: some View {
        if player.pageId != nil {
            Divider()
            PlayerBar(player: player, tokens: tokens, onOpenPage: openPage, onPrevCard: onPrevCard, onNextCard: onNextCard, onBand: onBand)
        }
    }
}

// MARK: - The shared page (LAB-1762: the one Agentic Engineering page every site shows, saved in the app at build)

extension LearnView {
    func sharedBody(_ loc: LearnShared.Location) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LearnSharedWeb(loc: loc, controller: shared, initialHash: sharedInitialHash())
                if let e = shared.error {
                    VStack(spacing: 8) {
                        Text("Learn could not load").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                        Text(e + ". Settings › Learn › classic screens shows the earlier screens.").font(.system(size: 12)).foregroundStyle(t.text2.color)
                    }
                    .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(t.window.color)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LearnPlayerBar(player: model.player, tokens: t, openPage: { sharedOpenPlaying() },
                           onPrevCard: model.learnDeck == nil ? nil : { sharedPlayCard(next: false) },
                           onNextCard: model.learnDeck == nil ? nil : { sharedPlayCard(next: true) },
                           onBand: model.learnDeck == nil ? nil : { sharedBackToBand() })
        }
        .background(t.window.color)
        .overlay(alignment: .top) { sharedToast }
        .onAppear { sharedAppear() }
        .onChange(of: model.learnTarget) { _, target in sharedTake(target) }
        .onChange(of: model.learnQuery) { _, _ in sharedTakeQuestion() }
        .onChange(of: LearnShared.mountOptions(t)) { _, _ in shared.theme(t, scale: textScale) }
        .onChange(of: textScale) { _, s in shared.theme(t, scale: s) }
        .onChange(of: model.settings.learnAutoAdvance) { _, _ in shared.theme(t, scale: textScale) }
    }

    /// Where the page opens: a pending link or question is taken on appear; else where it was last time Learn showed.
    private func sharedInitialHash() -> String? {
        model.learnTarget == nil && model.learnQuery == nil ? LearnSharedController.lastHash : nil
    }

    private func sharedAppear() {
        shared.model = model
        shared.theme(t, scale: textScale)
        model.loadLearn()
        guard !sharedAppeared else { sharedTakeQuestion(); return }
        sharedAppeared = true
        if model.learnQuery != nil { sharedTakeQuestion() }
        else if let target = model.learnTarget { sharedTake(target) }
    }

    /// LAB-1837 · every way into Learn (a link, Search, the Plan panel, Foundations › Skills, the mini player) opens the page
    /// where the classic screens would: a card, a band at its track, Radio; One Roof Help stays the window's Help page.
    private func sharedTake(_ target: String?) {
        guard let target else { return }
        let help = AppResources.helpFolder
        let route = model.learnDeck?.route(target, helpFolder: help)
            ?? (help.map { target.hasPrefix($0 + "/") } == true ? .help(target) : .none)
        if case .help(let page) = route { v2OpenHelp(page); return }
        if let h = LearnShared.hash(route) { shared.go(h) }
    }

    /// "How do I…": the best card; no question: the search field; no match: All cards › search with the question.
    private func sharedTakeQuestion() {
        guard let q = model.learnQuery else { return }
        model.learnQuery = nil
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { shared.search(""); return }
        if let best = model.learnDeck?.bestCards(for: question, limit: 1).first { shared.go(LearnShared.hash(.card(best)) ?? "#ae/radio") }
        else { shared.search(question) }
    }

    /// The player bar's title: the playing card's screen.
    private func sharedOpenPlaying() {
        guard let id = model.player.pageId, let slug = model.learnDeck?.slug(forPage: id) else { return }
        shared.go(LearnShared.hash(.card(slug)) ?? "#ae/radio")
    }

    /// ⏮ ⏭ on the player bar: the previous or next card in the roll-over order plays on (its screen opens when a card shows).
    private func sharedPlayCard(next: Bool) {
        guard let deck = model.learnDeck, let id = model.player.pageId, let slug = deck.slug(forPage: id) else { return }
        guard let k = next ? LearnRollover.next(after: slug, in: deck) : LearnRollover.previous(before: slug, in: deck) else { return }
        let audio = LearnAudio(deck: deck, player: model.player, nav: lnav)
        shared.pauseMedia()
        audio.play(k, then: audio.bandFrom(k))
        if shared.hash.hasPrefix("#ae/card/") { shared.go(LearnShared.hash(.card(k)) ?? "#ae/radio") }
    }

    /// Back to band from the player bar: the playing card's band.
    private func sharedBackToBand() {
        guard let deck = model.learnDeck, let id = model.player.pageId, let slug = deck.slug(forPage: id) else { return }
        shared.go(LearnShared.hash(.band(deck.band(of: slug).id, track: nil)) ?? "#ae/radio")
    }

    @ViewBuilder private var sharedToast: some View {
        if !shared.toast.isEmpty {
            let d = t.display
            Text(shared.toast).font(.system(size: 13)).foregroundStyle(d.text.color)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(d.fill.color).shadow(color: t.text.color.opacity(0.25), radius: 12, y: 8))
                .padding(.top, 72)
                .transition(.opacity)
        }
    }
}

// MARK: - v2 (LAB-1233 · handover A12.2; 1.9.2 LAB-1274: Radio · Writing · All cards, no Pages)

extension LearnView {
    /// One header (breadcrumb · section left; card actions, Radio · Writing · All cards and search right), the place
    /// below it, and the player bar at the foot.
    var v2Body: some View {
        VStack(spacing: 0) {
            v2RadioHeader
            V2LearnRadio(model: model, player: model.player, nav: lnav, deck: deck, posts: posts)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LearnPlayerBar(player: model.player, tokens: t, openPage: { v2OpenPlaying() },
                           onPrevCard: deck == nil ? nil : { v2PlayCard(next: false) },
                           onNextCard: deck == nil ? nil : { v2PlayCard(next: true) },
                           onBand: deck == nil ? nil : { v2BackToBand() })
        }
        .background(t.window.color)
        .overlay(alignment: .top) { v2Toast }
        .onAppear { v2Appear() }
        .onChange(of: model.learnTarget) { _, target in v2Take(target) }
        .onChange(of: model.learnQuery) { _, _ in v2TakeQuestion() }
        .onChange(of: model.settings.learnFolders) { _, _ in v2LoadPosts() }
        .onChange(of: blog.revision) { _, _ in v2LoadPosts() }
    }

    private func v2Appear() {
        model.loadLearn()
        if deck == nil { deck = model.learnDeck }
        v2LoadPosts()
        blog.refresh()
        guard !appeared else { v2TakeQuestion(); return }
        appeared = true
        if model.learnQuery != nil { v2TakeQuestion() }
        else if let target = model.learnTarget { v2Take(target) }
    }

    private func v2LoadPosts() {
        let folders = model.settings.learnFolders
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LearnPosts.all(folders: folders, hubCache: BlogHub.cacheDir)
            DispatchQueue.main.async { posts = found }
        }
    }

    /// LAB-1274 · a link, Search's Learn result, the Plan panel, Foundations › Skills, the mini player: a deck card opens
    /// its station; a field-manual page its band (at the track) or Radio; a One Roof Help page the window's Help page.
    /// Anything else (an extra-folder page) leaves Learn where it is.
    private func v2Take(_ target: String?) {
        guard let target else { return }
        let help = AppResources.helpFolder
        let route = deck?.route(target, helpFolder: help)
            ?? (help.map { target.hasPrefix($0 + "/") } == true ? .help(target) : .none)
        switch route {
        case .card(let slug): lnav.openCard(slug, scene: model.player.pageId == target ? model.player.index : 0)
        case .band(let id, let track): lnav.openBand(id, track: track)
        case .radio: lnav.go(.radio)
        case .help(let page): v2OpenHelp(page)
        case .none: break
        }
    }

    /// LAB-1274 · "How do I…" (menu ⌥⌘/, palette, the Plan panel's "More: how do I…"): the best-matching card's station.
    /// No question: the search field takes the keyboard. No match: All cards › How do I… shows the question (nothing found).
    private func v2TakeQuestion() {
        guard let q = model.learnQuery else { return }
        model.learnQuery = nil
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { lnav.focusSearch += 1; return }
        guard let deck else { return }
        if let best = deck.bestCards(for: question, limit: 1).first { lnav.query = ""; lnav.openCard(best) }
        else { lnav.query = question; lnav.go(.library) }
    }

    /// One Roof Help lives on the window's Help page (B4.1), open at `page`.
    private func v2OpenHelp(_ page: String) {
        model.helpTarget = page
        (NSApp.delegate as? AppDelegate)?.openHelp(nil)
    }

    /// LAB-1629 · ⏮ ⏭ on the player bar: the previous or next card in the roll-over order plays on (and its station opens
    /// when a card station is showing).
    private func v2PlayCard(next: Bool) {
        guard let deck, let id = model.player.pageId, let slug = deck.slug(forPage: id) else { return }
        guard let k = next ? LearnRollover.next(after: slug, in: deck) : LearnRollover.previous(before: slug, in: deck) else { return }
        let audio = LearnAudio(deck: deck, player: model.player, nav: lnav)
        audio.play(k, then: audio.bandFrom(k))
        if lnav.place == .card { lnav.openCard(k) }
    }

    /// LAB-1629 · back to band from the player bar: the band (or Radio) the card was opened from.
    private func v2BackToBand() {
        guard let deck else { return }
        let slug = lnav.place == .card ? lnav.slug : (model.player.pageId.flatMap { deck.slug(forPage: $0) } ?? lnav.slug)
        lnav.backToBand(slug, in: deck)
    }

    /// The player bar's title: the card station of the card playing.
    private func v2OpenPlaying() {
        guard let id = model.player.pageId, let slug = deck?.slug(forPage: id) else { return }
        lnav.openCard(slug, scene: model.player.index)
    }

    // MARK: Header (A12.2)

    private var v2RadioHeader: some View {
        let (crumbs, section) = v2Crumbs()
        return LearnHeaderRow {
            LearnCrumbs(crumbs: crumbs, section: section)
        } right: {
            if lnav.place == .card, let deck, deck.cards[lnav.slug] != nil {
                LearnCardActions(model: model, nav: lnav, player: model.player, audio: LearnAudio(deck: deck, player: model.player, nav: lnav))
            }
            if let deck {   // without a deck: the neutral no-deck state, nothing to switch or search
                LearnModeControl(nav: lnav)
                LearnSearchField(nav: lnav, total: deck.count)
            }
        }
    }

    private func v2Crumbs() -> ([LearnCrumbs.Crumb], String) {
        let home = LearnCrumbs.Crumb(label: "Learn") { lnav.go(.radio) }
        guard let deck else { return ([.init(label: "Learn")], "Agentic Engineering") }
        switch lnav.place {
        case .band:
            let b = deck.band(id: lnav.band)
            // LAB-1247: the band is opened from Radio home, so the way back names it.
            return ([home, .init(label: "Radio") { lnav.go(.radio) }, .init(label: "\(b.n) \(b.title)")], "Band")
        case .card:
            let b = deck.band(of: lnav.slug), c = deck.cards[lnav.slug]
            return ([home, .init(label: "\(b.n) \(b.title)") { lnav.openBand(b.id) }, .init(label: c?.title ?? lnav.slug)],
                    "Agentic Engineering · " + (c?.track ?? ""))
        case .post:
            return ([home, .init(label: "Writing") { lnav.go(.writing) }, .init(label: posts.first { $0.slug == lnav.post }?.title ?? "")], "Post")
        case .writing:
            return ([home, .init(label: "Writing")], "Broadcast schedule")
        case .path:
            return ([home, .init(label: deck.paths.first { $0.id == lnav.path }?.title ?? "")], "Programme")
        case .library:
            var c = [home, LearnCrumbs.Crumb(label: "All cards") { lnav.libSel = nil; lnav.query = "" }]
            if lnav.query.isEmpty, let sel = lnav.libSel { c.append(.init(label: v2BlockName(sel))) }
            return (c, !lnav.query.isEmpty ? "How do I…" : lnav.lens == "loop" ? "By band" : lnav.lens == "folder" ? "By folder" : "By kind")
        default:
            return ([.init(label: "Learn")], "Agentic Engineering · Radio")
        }
    }

    /// "loops:rhythms" → "Daily loops"; "loops:start" → "Start here"; "kind:vault" → "Notes & memory".
    private func v2BlockName(_ id: String) -> String {
        // By folder: "folder:skills/doctrine" → "doctrine/", a file → its name.
        if id.hasPrefix("folder:") {
            let rel = String(id.dropFirst(7)), name = (rel as NSString).lastPathComponent
            let isDir = deck.flatMap { DeckFolders.entry(rel, in: $0) }?.isDir ?? !name.contains(".")
            return isDir ? name + "/" : name
        }
        let tail = String(id.split(separator: ":").last ?? "")
        return tail == "start" ? "Start here" : LearnDeck.trackNames[tail]?.name ?? LearnDeck.label(tail)
    }

    @ViewBuilder private var v2Toast: some View {
        if !lnav.toast.isEmpty {
            let d = t.display
            Text(lnav.toast).font(.system(size: 13)).foregroundStyle(d.text.color)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(d.fill.color).shadow(color: t.text.color.opacity(0.25), radius: 12, y: 8))
                .padding(.top, 72)
                .transition(.opacity)
        }
    }
}
