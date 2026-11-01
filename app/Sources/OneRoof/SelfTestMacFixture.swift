import Foundation
import OneRoofCore

/// LAB-853 · self-test data for Resources › "This Mac, by app", so the browser tab list can be captured without asking the
/// owner's real browser anything (an Apple Event to Chrome would make macOS prompt the owner as One Roof).
///   ONEROOF_SELFTEST_MACFIXTURE=tabs|windows Chrome open, 78 renderer processes, tabs read (by window)
///   ONEROOF_SELFTEST_MACFIXTURE=sites      the same, grouped by site
///   ONEROOF_SELFTEST_MACFIXTURE=notasked   macOS has not asked yet: the one-line explanation and the ask button
///   ONEROOF_SELFTEST_MACFIXTURE=denied     the owner said no: where to allow it
///   ONEROOF_SELFTEST_MACFIXTURE=safari     LAB-2060: Safari open instead of Chrome (closes by position)
///   ONEROOF_SELFTEST_MACFIXTURE=brave      LAB-2060: Brave Browser open (read-only: its tabs are listed, never closed)
/// The fixture tabs go through `BrowserTabs.parse`, the parser the real AppleScript output goes through.
/// LAB-2052 / LAB-2053: with any mode the fixture also has a One Roof leftover (a local model left by a force-quit, the
/// warning row), Chrome helpers on both sides of the "Using a lot" lines (GPU 640 MB and a 300 MB renderer and a
/// renderer at 15 % CPU are big; Storage at 240 MB / 9 % and Audio are not) and three running sessions (Ready, Idle,
/// Working; one over roofd's warning line) with ten minutes of history, so the pills, bars and sparklines can be captured.
/// LAB-2054 · close actions never reach a browser while the fixture is on: they log `close tab <id>` /
/// `close window <id>` to <ONEROOF_SELFTEST_OUT>.tabclose.txt and drop the row from the fixture. To drive them:
///   ONEROOF_SELFTEST_TABCLOSE=tab:<tabId>,window:<windowId>,ask:<windowId>,hung:<tabId>,changed:<tabId>
///       tab: closes that tab · window: closes that window (no dialog) · ask: presses Close window (the dialog shows
///       for ≥ 2 tabs) · hung: the browser does not answer (the Force quit path) · changed: the tab moved (refresh)
///   ONEROOF_SELFTEST_TABHOVER=<tabId>      draws that tab row as hovered (its ✕ shows)
///   ONEROOF_SELFTEST_ALLPROCS=1            LAB-2053: opens "All processes (N)" under the browser
/// Fixture tab ids are <window id> × 10 + position − 1 (window 1201's tabs are 12010 … 12016).
enum SelfTestMacFixture {
    static var mode: String? { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_MACFIXTURE"] }
    static var browserName: String {
        switch mode {
        case "safari": return "Safari"
        case "brave": return "Brave Browser"
        default: return "Google Chrome"
        }
    }
    static var chromeId: String { "/Applications/\(browserName).app" }

    static var breakdown: MacBreakdown? {
        guard mode != nil else { return nil }
        let name = browserName
        let base = "/Applications/\(name).app/Contents/Frameworks/\(name) Framework.framework/Versions/1/Helpers/"
        var procs: [MacProc] = [MacProc(pid: 900, ppid: 1, name: name, path: "/Applications/\(name).app/Contents/MacOS/\(name)",
                                        kind: "Browser", footprint: 612 << 20, cpu: 3.1)]
        procs.append(MacProc(pid: 901, ppid: 900, name: "\(name) Helper (GPU)", path: base + "\(name) Helper (GPU).app", kind: "GPU",
                             footprint: 640 << 20, cpu: 4.2, endable: true))
        procs.append(MacProc(pid: 902, ppid: 900, name: "\(name) Helper", path: base + "\(name) Helper.app", kind: "Network",
                             footprint: 48 << 20, cpu: 0.2, endable: true))
        procs.append(MacProc(pid: 903, ppid: 900, name: "\(name) Helper", path: base + "\(name) Helper.app", kind: "Storage",
                             footprint: 240 << 20, cpu: 9, endable: true))
        procs.append(MacProc(pid: 904, ppid: 900, name: "\(name) Helper", path: base + "\(name) Helper.app", kind: "Audio",
                             footprint: 12 << 20, cpu: 0.1, endable: true))
        for i in 0..<78 {
            // Every renderer under the lines (≤ 239 MB, < 1 % CPU) but two: one at 300 MB, one at 15 % CPU.
            let mb: UInt64 = i == 5 ? 300 : UInt64(40 + (i * 37) % 200)
            let cpu: Double = i == 9 ? 15 : Double(i % 7) / 10
            procs.append(MacProc(pid: Int32(1000 + i), ppid: 900, name: "\(name) Helper (Renderer)", path: base + "\(name) Helper (Renderer).app",
                                 kind: BrowserTabs.rendererKind, footprint: mb << 20, cpu: cpu, endable: true))
        }
        procs.sort { $0.footprint > $1.footprint }
        let browser = MacAppGroup(id: chromeId, name: name, bundlePath: chromeId, mainPid: 900, procs: procs, quittable: true)
        let finder = MacAppGroup(id: "/System/Library/CoreServices/Finder.app", name: "Finder", bundlePath: "/System/Library/CoreServices/Finder.app",
                                 procs: [MacProc(pid: 400, ppid: 1, name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                                                 footprint: 180 << 20, cpu: 0.1)], quittable: true)
        let model = MacProc(pid: 777, ppid: 1, name: "llama-server", path: "/opt/homebrew/bin/llama-server", kind: "Local model",
                            footprint: 2_150 << 20, cpu: 0, endable: true)
        let oneRoof = MacAppGroup(id: "oneroof", name: "One Roof", procs: [model], isOneRoof: true, leftovers: [model])
        return MacBreakdown(groups: [browser, oneRoof, finder], unreadable: 212,
                            mac: MacMemory(total: 36 << 30, used: 24 << 30, swapUsed: 1 << 30, pressure: .normal))
    }

    /// What `listScript` would print for three windows (record and field separators as the script writes them), less
    /// what a fixture close removed.
    static var tabsOutput: String {
        let w: [(String, [(String, String)])] = [
            ("1201", [("https://linear.app/example/project/ui-redesign", "UI redesign · Linear"),
                      ("https://github.com/example/app/pulls", "Pull requests · example/app"),
                      ("https://blog.example.com/one-roof-builds-one-roof", "One Roof builds One Roof · Example blog"),
                      ("https://ci.example.com/repos/12/pipeline/418", "Pipeline #418 · Woodpecker"),
                      ("https://kargo.example.com/project/app", "app · Kargo"),
                      ("https://developer.apple.com/documentation/coreservices/1543363-aedeterminepermissiontoautomatet", "AEDeterminePermissionToAutomateTarget | Apple Developer"),
                      ("https://github.com/example/app/issues/41", "Machine view: name Chrome tabs · Issue #41")]),
            ("1187", [("https://mail.google.com/mail/u/0/#inbox", "Inbox (3) · Gmail"),
                      ("https://calendar.google.com/calendar/r/week", "Google Calendar · Week of 26 October"),
                      ("https://docs.google.com/document/d/abc/edit", "Field manual draft · Google Docs"),
                      ("chrome://settings/", "Settings")]),
            ("1150", [("https://www.youtube.com/watch?v=x", "Talk: Agents that close loops · YouTube"),
                      ("https://news.ycombinator.com/", "Hacker News"),
                      ("about:blank", "")]),
        ]
        var out = ""
        for (wid, tabs) in w where !closed.contains("window:" + wid) {
            var i = 0
            for (n, t) in tabs.enumerated() {
                let id = "\(Int(wid)! * 10 + n)"
                guard !closed.contains("tab:" + id) else { continue }
                i += 1
                out += [wid, "\(i)", id, i == 1 ? "true" : "false", t.0, t.1].joined(separator: "\u{1F}") + "\u{1E}"
            }
        }
        return out
    }

    // MARK: Closing (LAB-2054): never the real browser

    /// Tabs and windows a fixture close removed ("tab:<id>", "window:<id>").
    nonisolated(unsafe) static var closed: Set<String> = []

    /// What a close does in the fixture: log it, drop the row, answer as the browser would.
    static func close(_ target: BrowserTabs.CloseTarget) -> BrowserTabs.CloseOutcome {
        let line: String
        switch target {
        case .tab(let t):
            if outcomes["hung:" + t.tabId] != nil { log("close tab \(t.tabId) → no answer (hung)"); return .timedOut }
            if outcomes["changed:" + t.tabId] != nil { log("close tab \(t.tabId) → changed"); return .changed }
            closed.insert("tab:" + t.tabId); line = "close tab \(t.tabId)"
        case .window(let id, _, _):
            closed.insert("window:" + id); line = "close window \(id)"
        }
        log(line)
        return .closed
    }

    /// ONEROOF_SELFTEST_TABCLOSE as kind:id pairs, in order.
    static var actions: [(kind: String, id: String)] {
        (ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_TABCLOSE"] ?? "").split(separator: ",").compactMap { a in
            let p = a.split(separator: ":", maxSplits: 1).map(String.init)
            return p.count == 2 ? (p[0], p[1]) : nil
        }
    }
    private static var outcomes: [String: Bool] {
        Dictionary(actions.filter { $0.kind == "hung" || $0.kind == "changed" }.map { ($0.kind + ":" + $0.id, true) }, uniquingKeysWith: { a, _ in a })
    }
    static var allProcesses: Bool { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_ALLPROCS"] == "1" }
    static var hoverTab: String? { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_TABHOVER"] }

    private static func log(_ line: String) {
        let path = (ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_OUT"] ?? "/tmp/oneroof") + ".tabclose.txt"
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: Running sessions (LAB-2052: pills, sparklines and headroom bars to capture)

    static let sessionIds = ["fixture-ready", "fixture-idle", "fixture-working"]

    static func sessionTitle(_ rid: String) -> String? {
        guard mode != nil else { return nil }
        switch rid {
        case "fixture-ready": return "Flaky login test"
        case "fixture-idle": return "Nightly usage export"
        case "fixture-working": return "Help map as a tree"
        default: return nil
        }
    }

    static func sessionStatus(_ rowId: String) -> SessionStatus? {
        guard mode != nil else { return nil }
        switch rowId {
        case "runtime:fixture-ready": return .done
        case "runtime:fixture-idle": return .idle
        case "runtime:fixture-working": return .running
        default: return nil
        }
    }

    /// The sessions' usage at sample `k` (0 = ten minutes ago … 199 = now): a gentle wave, one holder past 1 GB.
    static func sessions(at k: Int) -> [String: SessionUsage] {
        guard mode != nil else { return [:] }
        func usage(_ rid: String, holderMB: Double, agentMB: Double, cpu: Double, pid: Int32) -> SessionUsage {
            let wave = 1 + 0.12 * sin(Double(k) / 9 + Double(pid))
            let holder = ProcUsage(pid: pid, ppid: 1, name: "roofd", depth: 0, role: .holder, footprint: UInt64(holderMB * wave) << 20, cpu: 0.3)
            let agent = ProcUsage(pid: pid + 1, ppid: pid, name: "claude", depth: 1, role: .agent, footprint: UInt64(agentMB * wave) << 20,
                                  cpu: cpu * wave)
            return SessionUsage(runtimeId: rid, holderPid: pid, procs: [holder, agent])
        }
        return ["fixture-ready": usage("fixture-ready", holderMB: 380, agentMB: 410, cpu: 1.2, pid: 5100),
                "fixture-idle": usage("fixture-idle", holderMB: 160, agentMB: 220, cpu: 0.2, pid: 5200),
                "fixture-working": usage("fixture-working", holderMB: 1_150, agentMB: 640, cpu: 38, pid: 5300)]
    }
}
