import AppKit
import Combine
import SwiftUI
import WebKit
import OneRoofCore

// LAB-1835 · Learn as the shared Agentic Engineering page (the `ggae` embed every site shows), from the copy saved in the app at
// build. A web view loads `oneroof-learn://hub/index.html`; `LearnSchemeHandler` answers every request from the saved files and
// the bundled deck (`LearnShared.respond`), so Learn needs no network. LAB-1836: the page's bridge posts to `LearnSharedController`,
// which runs One Roof's own actions (Play in One Roof, Use in a session ▾, Show in Finder, open in the browser). LAB-1893: the
// page also asks the app (`/app/…`, LearnSharedApp: posts, a post's text, the deck on disk, the search ranking) and hears from
// it (`oneroofLearnEmit`: the player's state, "posts changed"), so it does what the native screens did.

/// Answers `oneroof-learn://` requests from the saved page and the deck, off the main thread.
final class LearnSchemeHandler: NSObject, WKURLSchemeHandler {
    let loc: LearnShared.Location
    private let queue = DispatchQueue(label: "oneroof.learn.scheme", qos: .userInitiated)
    /// Tasks WebKit stopped (a frame went away): never answered after that.
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    /// LAB-1893 · what the app knows, kept current by the controller (read off the main thread).
    private var appState: LearnSharedApp
    var app: LearnSharedApp {
        get { lock.lock(); defer { lock.unlock() }; return appState }
        set { lock.lock(); appState = newValue; lock.unlock() }
    }

    init(_ loc: LearnShared.Location) { self.loc = loc; appState = LearnSharedApp(deck: nil, deckRoot: loc.deck) }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let range = task.request.value(forHTTPHeaderField: "Range")
        let id = ObjectIdentifier(task)
        let app = app
        queue.async { [loc] in
            let r = app.respond(path: url.path, query: url.query) ?? LearnShared.respond(path: url.path, range: range, at: loc)
            DispatchQueue.main.async {
                guard !self.take(id) else { return }
                let resp = HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.allHeaders)!
                task.didReceive(resp)
                task.didReceive(r.body)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }

    /// True when the task was stopped (and forgets it).
    private func take(_ id: ObjectIdentifier) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.remove(id) != nil
    }
}

/// The page's state and its bridge to One Roof (one per Learn view).
@MainActor
final class LearnSharedController: ObservableObject {
    weak var web: WKWebView?
    weak var model: AppModel? { didSet { if model !== oldValue { observe() } } }
    var loc: LearnShared.Location?
    /// LAB-1893 · the scheme handler that answers the page's `/app/…` questions.
    weak var scheme: LearnSchemeHandler? { didSet { if posts == nil && model != nil { loadPosts() } else { pushApp() } } }
    private var posts: [LearnPost]?
    private var watching = Set<AnyCancellable>()
    private var lastPlayer = ""
    private var lastPlayerAt = Date.distantPast
    private var wasPlaying = false
    private var kickers: [String: [String]] = [:]
    @Published var toast = ""
    /// Set once the embed mounted (the page posted `mounted`).
    @Published private(set) var mounted = false
    @Published private(set) var error: String?
    /// http(s) resources the page loaded (debug: offline there are none).
    private(set) var network: [String] = []
    /// The page's current screen (`#ae/…`), and the last one any Learn view showed (Learn reopens there).
    private(set) var hash = ""
    static var lastHash: String?
    /// The Learn view showing now (self-tests reach the page through it).
    static weak var current: LearnSharedController?
    private var themeKey = ""
    private var pendingHash: String?
    private var pendingSearch: String?
    private var toastWork: DispatchWorkItem?

    /// Open the page at an embed screen (`#ae/card/<slug>` …): now if it is mounted, else as soon as it is.
    func go(_ hash: String) {
        guard mounted, let web else { pendingHash = hash; return }
        web.evaluateJavaScript("location.hash = \(Self.js(hash))", completionHandler: nil)
    }

    /// "How do I…" with no match: All cards › search shows the question; empty: the search field takes the keyboard.
    func search(_ q: String) {
        guard mounted, let web else { pendingSearch = q; return }
        web.evaluateJavaScript("if (!location.hash.startsWith('#ae/cards')) location.hash = '#ae/cards'; setTimeout(function(){ oneroofLearnSearch(\(Self.js(q))) }, 0)", completionHandler: nil)
    }

    /// The centre theme's colours and fonts (and ⌘+ ⌘− as page zoom).
    func theme(_ t: ThemeTokens, scale: Double) {
        guard let web else { return }
        web.pageZoom = scale
        let opts = LearnShared.mountOptions(t, autoAdvance: autoAdvance)
        guard opts != themeKey, mounted else { return }
        themeKey = opts
        web.evaluateJavaScript("oneroofLearnMount(\(opts))", completionHandler: nil)
    }

    func pauseMedia() { web?.evaluateJavaScript("oneroofLearnPauseMedia && oneroofLearnPauseMedia()", completionHandler: nil) }

    func flash(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = "" }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }

    /// A message from the host page or a card frame.
    func receive(_ body: Any) {
        guard let msg = LearnBridgeMessage.parse(body) else { return }
        switch msg {
        case .ready:
            guard let model, let web else { return }
            let opts = LearnShared.mountOptions(model.themes.centre.tokens, autoAdvance: autoAdvance)
            themeKey = opts
            web.evaluateJavaScript("oneroofLearnMount(\(opts))", completionHandler: nil)
        case .mounted:
            mounted = true; error = nil
            pushApp()
            selfTest()
            if let h = pendingHash { pendingHash = nil; go(h) }
            if let q = pendingSearch { pendingSearch = nil; search(q) }
        case .hash(let h):
            hash = h
            if hash.hasPrefix("#ae/") { Self.lastHash = hash }
        case .error(let e): error = e
        case .net(let u):
            network.append(u)
            #if DEBUG
            NSLog("Learn (shared page): network request %@", u)
            #endif
        case .mediaPlay:
            if model?.player.playing == true { model?.player.pause() }    // audio never doubles
        case .play(let slug, let queue, let scene): play(slug, queue: queue, scene: scene ?? -1)
        case .useInSession(let slug): sessions(slug)
        case .openFolder(let p): openFolder(p)
        case .openExternal(let u): openExternal(u)
        case .subscribed: emitPlayer(force: true)
        case .toggle: toggle()
        case .rate:
            guard let p = model?.player else { return }
            p.rate = LearnShared.nextRate(after: p.rate, in: CoursePlayer.rates)
            emitPlayer(force: true)
        case .refreshPosts: LearnBlogFeed.shared.refresh(force: true)
        case .terminal(let p): terminal(p)
        }
    }

    // MARK: Bridge actions (LAB-1836)

    /// Play in One Roof: One Roof's player (keeps playing while you work), then `queue`, else the rest of the card's band.
    /// `scene` ≥ 0 (LAB-1893, Transcript › Play from here): from that scene.
    func play(_ slug: String, queue: [String], scene: Int = -1) {
        guard let model, let deck = model.learnDeck, deck.cards[slug] != nil else { return }
        let audio = LearnAudio(deck: deck, player: model.player, flash: { [weak self] in self?.flash($0) })
        pauseMedia()
        let rest = queue.isEmpty ? audio.bandFrom(slug) : queue
        let tracks = CourseAudio.tracks(page: deck.htmlPath(slug))
        guard !tracks.isEmpty else { flash("\(deck.cards[slug]?.title ?? slug) has no narration in this build"); return }
        if scene >= 0 { audio.play(slug, scene: scene, then: rest) } else { audio.toggle(slug, then: rest) }
    }

    /// Radio's ▶ / ❚❚, a playing card's header and play buttons: pause or resume One Roof's player.
    func toggle() {
        guard let p = model?.player, p.pageId != nil else { return }
        if !p.playing { pauseMedia() }
        p.toggle()
    }

    /// By folder › Open in Terminal: a new terminal session in that deck folder (One Roof's native panel did the same).
    func terminal(_ rel: String) {
        guard let loc, let model else { return }
        guard let full = LearnShared.folderInDeck(rel, deck: loc.deck) else { flash("Not a folder of this build's deck: \(rel)"); return }
        model.newTerminal(in: full)
        model.learnMode = false
    }

    // MARK: What the app knows (LAB-1893)

    /// Watch the player (its state goes to the page) and the posts (the hub's refresh, Settings › Learn folders).
    private func observe() {
        watching.removeAll()
        guard let model else { return }
        model.player.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.emitPlayer() }.store(in: &watching)
        model.player.clock.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.emitPlayer() }.store(in: &watching)
        LearnBlogFeed.shared.$revision.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.loadPosts() }.store(in: &watching)
        LearnBlogFeed.shared.$state.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.pushApp(); self?.emit(["type": "posts"]) }.store(in: &watching)
        loadPosts()
        LearnBlogFeed.shared.refresh()
    }

    /// The posts Learn shows (the hub's cache + Settings › Learn folders), read off the main thread; the page is told.
    func loadPosts() {
        guard let model, let loc else { return }
        let folders = model.settings.learnFolders, saved = loc.learn + "/posts.json"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = LearnSharedApp.posts(folders: folders, hubCache: BlogHub.cacheDir, saved: saved)
            DispatchQueue.main.async { [weak self] in
                self?.posts = found
                self?.pushApp()
                self?.emit(["type": "posts"])
            }
        }
    }

    /// The scheme handler's snapshot: the deck, the posts and Writing's source line.
    private func pushApp() {
        guard let scheme, let loc else { return }
        let feed: LearnSharedApp.Feed
        switch LearnBlogFeed.shared.state {
        case .idle, .loading: feed = .loading
        case .reached: feed = .reached
        case .offline(let why): feed = .offline(why)
        }
        let note = posts.map { LearnSharedApp.postsNote($0, feed: feed, savedAt: Self.when(LearnBlogFeed.shared.savedAt), blog: BlogHub.name) } ?? ""
        let offline: Bool = { if case .offline = feed { return true }; return false }()
        scheme.app = LearnSharedApp(deck: model?.learnDeck, deckRoot: loc.deck, posts: posts, postsNote: note, postsOffline: offline)
    }

    /// "10:42" today, else "24 Oct 2026, 10:42"; "earlier" when the copy was never saved.
    static func when(_ d: Date?) -> String {
        guard let d else { return "earlier" }
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
    }

    /// The player's state to the page: at once when what is loaded, playing or the scene changes; the time at most once a second.
    func emitPlayer(force: Bool = false) {
        guard let model, mounted else { return }
        let p = model.player
        let deck = model.learnDeck
        let slug = p.pageId.flatMap { deck?.slug(forPage: $0) }
        if p.playing && !wasPlaying { pauseMedia() }      // One Roof's player starting pauses the page (audio never doubles)
        wasPlaying = p.playing
        let kicker = slug.flatMap { k -> String? in
            if kickers[k] == nil, let deck { kickers[k] = DeckSpec.scenes(path: deck.specPath(k), fallback: deck.cards[k]).map(\.kicker) }
            return kickers[k].flatMap { $0.indices.contains(p.index) ? $0[p.index] : nil }
        }
        let key = "\(slug ?? "")|\(p.playing)|\(p.index)|\(p.tracks.count)|\(p.rate)"
        guard force || key != lastPlayer || (p.playing && Date().timeIntervalSince(lastPlayerAt) >= 1) else { return }
        lastPlayer = key; lastPlayerAt = Date()
        let np = LearnSharedApp.nowPlaying(slug: slug, playing: p.playing, index: p.index, count: p.tracks.count, clipElapsed: p.clock.elapsed,
                                           total: slug.flatMap { deck?.cards[$0]?.estSeconds } ?? 0, rate: p.rate, kicker: kicker)
        emit(["type": "player", "np": np])
    }

    /// ONEROOF_SELFTEST_LEARNJS=<s>@<js>[;;<s>@<js>…]: scripts run in the page that long after it first mounted (captures of
    /// a selected folder row, a typed search …). Once per run.
    /// LAB-1894: plus LEARNMODE's steps and the card page hooks (CARDENDED, PAGECLICK, PAGEJS), from LearnSharedSelfTest.
    private func selfTest() {
        let env = ProcessInfo.processInfo.environment
        guard SelfTest.isActive, !Self.selfTestRan else { return }
        Self.selfTestRan = true
        var steps = Self.selfTestSteps
        for one in (env["ONEROOF_SELFTEST_LEARNJS"] ?? "").components(separatedBy: ";;") {
            guard let at = one.firstIndex(of: "@") else { continue }
            steps.append(.init(Double(one[..<at]) ?? 1, String(one[one.index(after: at)...])))
        }
        steps += LearnSharedSelfTest.cardPageScripts(env).map { .init(0, $0) }
        for st in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + st.after) { [weak self] in self?.web?.evaluateJavaScript(st.js, completionHandler: nil) }
        }
    }
    private static var selfTestRan = false
    /// LEARNMODE's scripts (SelfTest sets them before Learn opens).
    static var selfTestSteps: [LearnSharedSelfTest.Step] = []
    /// Settings › Learn › Auto-advance, or off for a self-test with ONEROOF_SELFTEST_AUTOADVANCE=0.
    var autoAdvance: Bool? {
        guard let model else { return nil }
        return model.settings.learnAutoAdvance && ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_AUTOADVANCE"] != "0"
    }

    /// An event for the page's bridge subscribers (`oneroofLearnEmit`).
    private func emit(_ e: [String: Any]) {
        guard mounted, let web, let d = try? JSONSerialization.data(withJSONObject: e) else { return }
        web.evaluateJavaScript("window.oneroofLearnEmit && window.oneroofLearnEmit(\(String(decoding: d, as: UTF8.self)))", completionHandler: nil)
    }

    /// Use in a session ▾: the live agent sessions, as the classic card header lists them; the one picked gets /<slug>.
    func sessions(_ slug: String) {
        guard let model, LearnShared.isSlug(slug), let web else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let head = NSMenuItem(title: "Type /\(slug) as the next message in", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let live = model.sessionItems.filter { $0.liveAgent != nil && $0.session.agent.isAgent }
        if live.isEmpty {
            let none = NSMenuItem(title: "No live agent session. Start one, then send the card to it.", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for i in live {
            let id = i.id
            menu.addItem(LearnMenuItem(title: "\(i.session.name) · \(i.status.rawValue.capitalized)") { [weak self, weak model] in
                guard let model, let item = model.item(id) else { return }
                if item.status == .running { self?.flash("\(item.session.name) is working; send /\(slug) when it is idle") }
                else { model.sendSkill(slug, to: item); self?.flash("Sent /\(slug) to \(item.session.name)") }
            })
        }
        let at = web.convert(web.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        menu.popUp(positioning: nil, at: at, in: web)
    }

    /// Show in Finder: a file or folder of the bundled deck (a path from the deck root).
    func openFolder(_ rel: String) {
        guard let loc else { return }
        let base = (loc.deck as NSString).standardizingPath
        let full = ((base as NSString).appendingPathComponent(rel) as NSString).standardizingPath
        guard full == base || full.hasPrefix(base + "/"), FileManager.default.fileExists(atPath: full) else { flash("Not in this build's deck: \(rel)"); return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: full)])
    }

    /// A link that leaves the page: a deck page opens from disk in the browser, a post on its public page, a web link as itself.
    func openExternal(_ s: String) {
        guard let loc, let u = LearnShared.external(s, at: loc, hub: LearnShared.manifest(learn: loc.learn)?.hub ?? BlogHub.defaultBase) else { return }
        NSWorkspace.shared.open(u)
    }

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(decoding: d, as: UTF8.self).dropFirst().dropLast().description
    }
}

/// A menu item that runs a closure.
final class LearnMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

/// The web view (one per Learn view; kept while Learn shows).
struct LearnSharedWeb: NSViewRepresentable {
    let loc: LearnShared.Location
    let controller: LearnSharedController
    /// Where the page first opens (`#ae/…`).
    var initialHash: String?

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let scheme = LearnSchemeHandler(loc)
        cfg.setURLSchemeHandler(scheme, forURLScheme: LearnShared.scheme)
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        if SelfTest.isActive { cfg.websiteDataStore = .nonPersistent() }   // tests never read or write the owner's page storage
        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: LearnShared.frameScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if SelfTest.isActive, let st = LearnSharedSelfTest.startScript(ProcessInfo.processInfo.environment) {
            ucc.addUserScript(WKUserScript(source: st, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        ucc.add(LearnSharedMessages(controller), name: LearnShared.handler)
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        w.setAccessibilityLabel("Learn")
        controller.web = w
        controller.loc = loc
        controller.scheme = scheme
        w.load(URLRequest(url: LearnShared.pageURL(hash: initialHash)))
        return w
    }

    static func dismantleNSView(_ w: WKWebView, coordinator: Coordinator) {
        w.evaluateJavaScript("oneroofLearnPauseMedia && oneroofLearnPauseMedia()", completionHandler: nil)   // never leave a page talking
        w.configuration.userContentController.removeScriptMessageHandler(forName: LearnShared.handler)
        w.stopLoading()
    }

    func updateNSView(_ w: WKWebView, context: Context) { controller.web = w }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let controller: LearnSharedController
        init(_ c: LearnSharedController) { controller = c }

        /// The page and its card frames stay on oneroof-learn://; a clicked web link opens in the browser; nothing else loads.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.cancel); return }
            if scheme == LearnShared.scheme || scheme == "about" {
                // A main-frame link to a post or a deck file leaves the page (the bridge normally takes these first).
                if action.targetFrame?.isMainFrame == true, action.navigationType == .linkActivated, !url.path.isEmpty, url.path != "/index.html", url.path != "/" {
                    Task { @MainActor in controller.openExternal(url.absoluteString) }
                    decisionHandler(.cancel); return
                }
                decisionHandler(.allow); return
            }
            if action.navigationType == .linkActivated, scheme == "http" || scheme == "https" || scheme == "mailto" { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }

        /// target="_blank" and window.open: to the app (a deck page from disk, a post or web link in the browser).
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { Task { @MainActor in controller.openExternal(url.absoluteString) } }
            return nil
        }
    }
}

/// The page's messages, held weakly so the content controller does not keep the controller alive.
private final class LearnSharedMessages: NSObject, WKScriptMessageHandler {
    weak var owner: LearnSharedController?
    init(_ owner: LearnSharedController) { self.owner = owner }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in owner?.receive(body) }
    }
}
