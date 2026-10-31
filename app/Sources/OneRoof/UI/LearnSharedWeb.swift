import AppKit
import SwiftUI
import WebKit
import OneRoofCore

// LAB-1835 · Learn as the shared Agentic Engineering page (the `ggae` embed every site shows), from the copy saved in the app at
// build. A web view loads `oneroof-learn://hub/index.html`; `LearnSchemeHandler` answers every request from the saved files and
// the bundled deck (`LearnShared.respond`), so Learn needs no network. LAB-1836: the page's bridge posts to `LearnSharedController`,
// which runs One Roof's own actions (Play in One Roof, Use in a session ▾, Show in Finder, open in the browser).

/// Answers `oneroof-learn://` requests from the saved page and the deck, off the main thread.
final class LearnSchemeHandler: NSObject, WKURLSchemeHandler {
    let loc: LearnShared.Location
    private let queue = DispatchQueue(label: "oneroof.learn.scheme", qos: .userInitiated)
    /// Tasks WebKit stopped (a frame went away): never answered after that.
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    init(_ loc: LearnShared.Location) { self.loc = loc }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let range = task.request.value(forHTTPHeaderField: "Range")
        let id = ObjectIdentifier(task)
        queue.async { [loc] in
            let r = LearnShared.respond(path: url.path, range: range, at: loc)
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
    weak var model: AppModel?
    var loc: LearnShared.Location?
    @Published var toast = ""
    /// Set once the embed mounted (the page posted `mounted`).
    @Published private(set) var mounted = false
    @Published private(set) var error: String?
    /// http(s) resources the page loaded (debug: offline there are none).
    private(set) var network: [String] = []
    /// The page's current screen (`#ae/…`), and the last one any Learn view showed (Learn reopens there).
    private(set) var hash = ""
    static var lastHash: String?
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
        let opts = LearnShared.mountOptions(t, autoAdvance: model?.settings.learnAutoAdvance)
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
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "ready":
            guard let model, let web else { return }
            let opts = LearnShared.mountOptions(model.themes.centre.tokens, autoAdvance: model.settings.learnAutoAdvance)
            themeKey = opts
            web.evaluateJavaScript("oneroofLearnMount(\(opts))", completionHandler: nil)
        case "mounted":
            mounted = true; error = nil
            if let h = pendingHash { pendingHash = nil; go(h) }
            if let q = pendingSearch { pendingSearch = nil; search(q) }
        case "hash":
            hash = m["hash"] as? String ?? ""
            if hash.hasPrefix("#ae/") { Self.lastHash = hash }
        case "error": error = m["message"] as? String ?? "the page could not load"
        case "net":
            let u = m["url"] as? String ?? ""
            network.append(u)
            #if DEBUG
            NSLog("Learn (shared page): network request %@", u)
            #endif
        case "mediaPlay":
            if model?.player.playing == true { model?.player.pause() }    // audio never doubles
        case "play": play(m["slug"] as? String ?? "", queue: m["queue"] as? [String] ?? [])
        case "useInSession": sessions(m["slug"] as? String ?? "")
        case "openFolder": openFolder(m["path"] as? String ?? "")
        case "openExternal": openExternal(m["url"] as? String ?? "")
        default: break
        }
    }

    // MARK: Bridge actions (LAB-1836)

    /// Play in One Roof: One Roof's player (keeps playing while you work), then `queue`, else the rest of the card's band.
    func play(_ slug: String, queue: [String]) {
        guard let model, let deck = model.learnDeck, deck.cards[slug] != nil else { return }
        let audio = LearnAudio(deck: deck, player: model.player, nav: LearnNav(spec: "radio"))
        pauseMedia()
        let rest = queue.isEmpty ? audio.bandFrom(slug) : queue
        let tracks = CourseAudio.tracks(page: deck.htmlPath(slug))
        guard !tracks.isEmpty else { flash("\(deck.cards[slug]?.title ?? slug) has no narration in this build"); return }
        audio.toggle(slug, then: rest)
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
        cfg.setURLSchemeHandler(LearnSchemeHandler(loc), forURLScheme: LearnShared.scheme)
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        if SelfTest.isActive { cfg.websiteDataStore = .nonPersistent() }   // tests never read or write the owner's page storage
        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: LearnShared.frameScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.add(LearnSharedMessages(controller), name: LearnShared.handler)
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        w.setAccessibilityLabel("Learn")
        controller.web = w
        controller.loc = loc
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
