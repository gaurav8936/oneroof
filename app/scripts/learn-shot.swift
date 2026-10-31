// LAB-1838 · capture the shared Learn page exactly as One Roof shows it: the same host page, the same `oneroof-learn://` answers
// (LearnShared.respond) from a saved learn folder and a deck, the same colours (LearnShared.mountOptions of a One Roof theme), in
// an off-screen WKWebView. One PNG per screen, and a report of every http(s) request the page or a card frame made (offline there
// should be none). Run through scripts/learn-shot.sh (it links OneRoofCore). Touches no app, no roofd, no settings.
import AppKit
import OneRoofCore
import WebKit

struct Args {
    var learn = "", deck = "", out = "", theme = ThemeName.daylight, width = 1440.0, height = 900.0, wait = 3.0
    var routes: [String] = []
}

func parse() -> Args {
    var a = Args(), it = CommandLine.arguments.dropFirst().makeIterator()
    while let x = it.next() {
        switch x {
        case "--learn": a.learn = it.next() ?? ""
        case "--deck": a.deck = it.next() ?? ""
        case "--out": a.out = it.next() ?? ""
        case "--theme": a.theme = ThemeName(rawValue: it.next() ?? "") ?? .daylight
        case "--size":
            let p = (it.next() ?? "").split(separator: "x").compactMap { Double($0) }
            if p.count == 2 { a.width = p[0]; a.height = p[1] }
        case "--wait": a.wait = Double(it.next() ?? "") ?? 3
        default: a.routes.append(x)
        }
    }
    if a.routes.isEmpty { a.routes = ["#ae/radio"] }
    return a
}

final class Handler: NSObject, WKURLSchemeHandler {
    let loc: LearnShared.Location
    var log: [String] = []
    init(_ l: LearnShared.Location) { loc = l }
    func webView(_ w: WKWebView, start t: WKURLSchemeTask) {
        guard let url = t.request.url else { return }
        let r = LearnShared.respond(path: url.path, range: t.request.value(forHTTPHeaderField: "Range"), at: loc)
        log.append("\(r.status) \(url.path)")
        t.didReceive(HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.allHeaders)!)
        t.didReceive(r.body)
        t.didFinish()
    }
    func webView(_ w: WKWebView, stop t: WKURLSchemeTask) {}
}

final class Messages: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var mounted = false, ready = false, net: [String] = [], errors: [String] = [], bridge: [String] = []
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], let type = d["type"] as? String else { return }
        switch type {
        case "ready": ready = true
        case "mounted": mounted = true
        case "net": net.append(d["url"] as? String ?? "")
        case "error": errors.append(d["message"] as? String ?? "")
        case "hash", "mediaPlay": break
        default: bridge.append("\(type) \(d)")
        }
    }
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let s = a.request.url?.scheme ?? ""
        if s != LearnShared.scheme && s != "about" { net.append("navigation: \(a.request.url?.absoluteString ?? "")") }
        decisionHandler(s == LearnShared.scheme || s == "about" ? .allow : .cancel)
    }
}

func spin(_ seconds: Double, until: () -> Bool = { false }) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end, !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

let a = parse()
guard !a.learn.isEmpty, !a.deck.isEmpty, !a.out.isEmpty else {
    print("usage: learn-shot --learn <learn dir> --deck <deck dir> --out <dir> [--theme daylight|graphite|midnight] [--size 1440x900] [#ae/… …]")
    exit(2)
}
let problems = LearnShared.problems(learn: a.learn)
if !problems.isEmpty { print("learn folder problems: \(problems.joined(separator: "; "))"); exit(1) }
let loc = LearnShared.Location(learn: a.learn, deck: a.deck)
try? FileManager.default.createDirectory(atPath: a.out, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let handler = Handler(loc), msgs = Messages()
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: LearnShared.scheme)
cfg.websiteDataStore = .nonPersistent()
cfg.mediaTypesRequiringUserActionForPlayback = .all     // a capture never plays audio
cfg.userContentController.addUserScript(WKUserScript(source: LearnShared.frameScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
cfg.userContentController.add(msgs, name: LearnShared.handler)
let frame = NSRect(x: -20000, y: -20000, width: a.width, height: a.height)
let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: cfg)
web.navigationDelegate = msgs
win.contentView = web
win.orderBack(nil)

web.load(URLRequest(url: LearnShared.pageURL(hash: a.routes[0])))
spin(15) { msgs.ready || msgs.mounted }
web.evaluateJavaScript("oneroofLearnMount(\(LearnShared.mountOptions(a.theme.tokens)))", completionHandler: nil)
spin(15) { msgs.mounted }
if !msgs.mounted { print("FAIL the embed did not mount (\(msgs.errors.joined(separator: "; ")))"); exit(1) }

var shots: [String] = []
for (i, route) in a.routes.enumerated() {
    if i > 0 { web.evaluateJavaScript("location.hash = \(String(decoding: try! JSONSerialization.data(withJSONObject: [route]), as: UTF8.self).dropFirst().dropLast())", completionHandler: nil) }
    spin(a.wait)
    let name = String(format: "%02d-", i + 1) + route.replacingOccurrences(of: "#ae/", with: "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "#", with: "") + "-\(a.theme.rawValue).png"
    var done = false
    web.takeSnapshot(with: nil) { img, err in
        defer { done = true }
        guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed: \(String(describing: err))"); return }
        try? png.write(to: URL(fileURLWithPath: a.out + "/" + name))
        shots.append(name)
    }
    spin(10) { done }
}
let fails = handler.log.filter { $0.hasPrefix("4") || $0.hasPrefix("5") }
print("learn-shot: \(shots.count) screen(s) in \(a.out) (\(a.theme.rawValue), \(Int(a.width))x\(Int(a.height)))")
shots.forEach { print("  \($0)") }
print("scheme requests: \(handler.log.count), not found: \(fails.count)\(fails.isEmpty ? "" : " → " + fails.prefix(8).joined(separator: ", "))")
print("http(s) requests: \(msgs.net.count)\(msgs.net.isEmpty ? " (offline-clean)" : "")")
msgs.net.prefix(20).forEach { print("  \($0)") }
if !msgs.errors.isEmpty { print("page errors: \(msgs.errors.joined(separator: "; "))") }
exit(msgs.net.isEmpty && msgs.errors.isEmpty ? 0 : 3)
