import Foundation
import OneRoofCore

/// LAB-853 · self-test data for Machine › "This Mac, by app", so the browser tab list can be captured without asking the
/// owner's real browser anything (an Apple Event to Chrome would make macOS prompt the owner as One Roof).
///   ONEROOF_SELFTEST_MACFIXTURE=tabs       Chrome open, 78 renderer processes, tabs read (by window)
///   ONEROOF_SELFTEST_MACFIXTURE=sites      the same, grouped by site
///   ONEROOF_SELFTEST_MACFIXTURE=notasked   macOS has not asked yet: the one-line explanation and the ask button
///   ONEROOF_SELFTEST_MACFIXTURE=denied     the owner said no: where to allow it
/// The fixture tabs go through `BrowserTabs.parse`, the parser the real AppleScript output goes through.
enum SelfTestMacFixture {
    static var mode: String? { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_MACFIXTURE"] }
    static let chromeId = "/Applications/Google Chrome.app"

    static var breakdown: MacBreakdown? {
        guard mode != nil else { return nil }
        let base = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/"
        var procs: [MacProc] = [MacProc(pid: 900, ppid: 1, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                                        kind: "Browser", footprint: 612 << 20, cpu: 3.1)]
        procs.append(MacProc(pid: 901, ppid: 900, name: "Google Chrome Helper (GPU)", path: base + "Google Chrome Helper (GPU).app", kind: "GPU",
                             footprint: 690 << 20, cpu: 4.2, endable: true))
        procs.append(MacProc(pid: 902, ppid: 900, name: "Google Chrome Helper", path: base + "Google Chrome Helper.app", kind: "Network",
                             footprint: 48 << 20, cpu: 0.2, endable: true))
        for i in 0..<78 {
            procs.append(MacProc(pid: Int32(1000 + i), ppid: 900, name: "Google Chrome Helper (Renderer)", path: base + "Google Chrome Helper (Renderer).app",
                                 kind: BrowserTabs.rendererKind, footprint: UInt64(40 + (i * 37) % 260) << 20, cpu: Double(i % 7) / 10, endable: true))
        }
        procs.sort { $0.footprint > $1.footprint }
        let chrome = MacAppGroup(id: chromeId, name: "Google Chrome", bundlePath: chromeId, mainPid: nil, procs: procs)
        let finder = MacAppGroup(id: "/System/Library/CoreServices/Finder.app", name: "Finder", bundlePath: "/System/Library/CoreServices/Finder.app",
                                 procs: [MacProc(pid: 400, ppid: 1, name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                                                 footprint: 180 << 20, cpu: 0.1)])
        return MacBreakdown(groups: [chrome, finder], unreadable: 212,
                            mac: MacMemory(total: 36 << 30, used: 24 << 30, swapUsed: 1 << 30, pressure: .normal))
    }

    /// What `listScript` would print for three Chrome windows (record and field separators as the script writes them).
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
        for (wid, tabs) in w {
            for (i, t) in tabs.enumerated() {
                out += [wid, "\(i + 1)", "\(Int(wid)! * 10 + i)", i == 0 ? "true" : "false", t.0, t.1].joined(separator: "\u{1F}") + "\u{1E}"
            }
        }
        return out
    }
}
