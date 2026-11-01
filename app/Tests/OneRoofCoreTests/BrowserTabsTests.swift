import XCTest
@testable import OneRoofCore

/// LAB-554: a browser's tabs by name and site in Resources › This Mac.
final class BrowserTabsTests: XCTestCase {
    let fs = BrowserTabs.fieldSep, rs = BrowserTabs.recordSep

    func testBrowsersByAppName() {
        XCTAssertEqual(BrowserTabs.family(appName: "Google Chrome"), .chromium)
        XCTAssertEqual(BrowserTabs.family(appName: "Google Chrome Canary"), .chromium)
        XCTAssertEqual(BrowserTabs.family(appName: "Brave Browser"), .chromium)
        XCTAssertEqual(BrowserTabs.family(appName: "Microsoft Edge"), .chromium)
        XCTAssertEqual(BrowserTabs.family(appName: "Arc"), .chromium)
        XCTAssertEqual(BrowserTabs.family(appName: "Safari"), .safari)
        XCTAssertNil(BrowserTabs.family(appName: "Slack"))
        XCTAssertNil(BrowserTabs.family(appName: "Archive Utility"))
    }

    func testParseRecordsKeepsOrderAndTitlesWithTabsAndNewLines() {
        let out = ["1001", "1", "7", "false", "https://www.github.com/gaurav8936/oneroof/pull/12", "PR #12\tfix · GitHub"].joined(separator: fs) + rs
            + ["1001", "2", "9", "true", "https://linear.app/x/issue/LAB-554", "LAB-554\nDetails"].joined(separator: fs) + rs
            + "garbage" + rs + "\n"
        let tabs = BrowserTabs.parse(out)
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0], BrowserTab(windowId: "1001", index: 1, tabId: "7", active: false,
                                           url: "https://www.github.com/gaurav8936/oneroof/pull/12", title: "PR #12\tfix · GitHub"))
        XCTAssertTrue(tabs[1].active)
        XCTAssertEqual(tabs[1].site, "linear.app")
        XCTAssertEqual(tabs[1].id, "1001/9")
        XCTAssertEqual(BrowserTabs.parse(""), [])
    }

    func testSiteNames() {
        XCTAssertEqual(BrowserTabs.site("https://www.github.com/a"), "github.com")
        XCTAssertEqual(BrowserTabs.site("https://Docs.Google.com/d/1"), "docs.google.com")
        XCTAssertEqual(BrowserTabs.site("http://localhost:3939/"), "localhost")
        XCTAssertEqual(BrowserTabs.site("chrome://settings"), "Browser pages")
        XCTAssertEqual(BrowserTabs.site("chrome-extension://abc/popup.html"), "Browser pages")
        XCTAssertEqual(BrowserTabs.site("about:blank"), "Blank tab")
        XCTAssertEqual(BrowserTabs.site(""), "Blank tab")
        XCTAssertEqual(BrowserTabs.site("file:///Users/someone/a.html"), "Files on this Mac")
    }

    func testSitesGroupMostTabsFirstThenByName() {
        func tab(_ i: Int, _ url: String) -> BrowserTab { BrowserTab(windowId: "1", index: i, tabId: "\(i)", active: false, url: url, title: "t\(i)") }
        let s = BrowserTabs.sites([tab(1, "https://b.com/1"), tab(2, "https://a.com"), tab(3, "https://b.com/2"), tab(4, "https://c.com")])
        XCTAssertEqual(s.map(\.site), ["b.com", "a.com", "c.com"])
        XCTAssertEqual(s[0].tabs.map(\.index), [1, 3])
    }

    func testFailures() {
        XCTAssertNil(BrowserTabs.failure(status: 0, stderr: ""))
        XCTAssertEqual(BrowserTabs.failure(status: 1, stderr: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"), .notAllowed)
        XCTAssertEqual(BrowserTabs.failure(status: 1, stderr: "syntax error: nope\nmore"), .failed("syntax error: nope"))
    }

    func testScriptsNameTheAppSafelyAndNeverLaunchIt() {
        let s = BrowserTabs.listScript(app: "Odd \"Name\"", family: .chromium)
        XCTAssertTrue(s.hasPrefix("if application \"Odd \\\"Name\\\"\" is not running then return \"\""))
        let t = BrowserTab(windowId: "12", index: 3, tabId: "456", active: false, url: "", title: "")
        XCTAssertTrue(BrowserTabs.showScript(app: "Google Chrome", family: .chromium, tab: t).contains("if id of t is 456 then set active tab index of w to i"))
        XCTAssertTrue(BrowserTabs.showScript(app: "Safari", family: .safari, tab: t).contains("set current tab of w to tab 3 of w"))
    }

    /// LAB-853: what the list script prints for Chrome with two windows (window 1201 in front) → tabs by window.
    func testTabsGroupByWindowInTheBrowsersOrder() {
        let fs = "\u{1F}", rs = "\u{1E}"
        func rec(_ w: String, _ i: Int, _ id: String, _ active: Bool, _ url: String, _ title: String) -> String {
            [w, "\(i)", id, active ? "true" : "false", url, title].joined(separator: fs) + rs
        }
        let out = rec("1201", 1, "11", false, "https://linear.app/example/project/x", "Project · Linear")
            + rec("1201", 2, "12", true, "https://github.com/gaurav8936/oneroof/pulls", "Pull requests")
            + rec("1187", 1, "21", true, "https://mail.google.com/mail/u/0/#inbox", "Inbox (3) · Gmail")
            + rec("1201", 3, "13", false, "chrome://settings/", "Settings")
            + rec("1187", 2, "22", false, "about:blank", "")
            + "garbage" + rs
        let tabs = BrowserTabs.parse(out)
        XCTAssertEqual(tabs.count, 5)
        let w = BrowserTabs.windows(tabs)
        XCTAssertEqual(w.map(\.windowId), ["1201", "1187"])
        XCTAssertEqual(w.map(\.number), [1, 2])
        XCTAssertEqual(w[0].tabs.map(\.title), ["Project · Linear", "Pull requests", "Settings"])
        XCTAssertEqual(w[0].tabs.map(\.site), ["linear.app", "github.com", "Browser pages"])
        XCTAssertEqual(w[0].front?.tabId, "12")
        XCTAssertEqual(w[1].tabs.map(\.site), ["mail.google.com", "Blank tab"])
        XCTAssertEqual(BrowserTabs.windows([]), [])
    }

    func testAutomationPermissionFromStatus() {
        XCTAssertEqual(BrowserTabs.permission(status: 0), .granted)
        XCTAssertEqual(BrowserTabs.permission(status: -1744), .notAsked)
        XCTAssertEqual(BrowserTabs.permission(status: -1743), .denied)
        XCTAssertEqual(BrowserTabs.permission(status: -600), .notRunning)
        XCTAssertEqual(BrowserTabs.permission(status: -50), .unknown(-50))
    }

    /// The 78 anonymous "Tab or site" rows fold into one: how many and their memory together.
    func testRenderersCountAndMemory() {
        var procs = (0..<78).map { MacProc(pid: Int32(1000 + $0), ppid: 900, name: "Google Chrome Helper (Renderer)", path: "/x",
                                           kind: BrowserTabs.rendererKind, footprint: 10 << 20) }
        procs.append(MacProc(pid: 901, ppid: 900, name: "Google Chrome Helper (GPU)", path: "/x", kind: "GPU", footprint: 500 << 20))
        let r = BrowserTabs.renderers(procs)
        XCTAssertEqual(r.count, 78)
        XCTAssertEqual(r.bytes, 780 << 20)
        XCTAssertEqual(BrowserTabs.renderers([]).count, 0)
    }

    /// The scripts compile against the real browsers' dictionaries (macOS only, when the browser is installed).
    func testScriptsCompile() throws {
        #if os(macOS)
        let compiler = "/usr/bin/osacompile"
        guard FileManager.default.isExecutableFile(atPath: compiler) else { throw XCTSkip("no osacompile") }
        let t = BrowserTab(windowId: "12", index: 3, tabId: "456", active: false, url: "", title: "")
        var checked = 0
        for (app, fam) in [("Google Chrome", BrowserTabs.Family.chromium), ("Safari", .safari)]
        where FileManager.default.fileExists(atPath: "/Applications/\(app).app") || app == "Safari" {
            for script in [BrowserTabs.listScript(app: app, family: fam), BrowserTabs.showScript(app: app, family: fam, tab: t)] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: compiler)
                p.arguments = ["-o", NSTemporaryDirectory() + "oneroof-browser-tabs-\(getpid()).scpt", "-e", script]
                let err = Pipe(); p.standardError = err
                try p.run(); p.waitUntilExit()
                let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                XCTAssertEqual(p.terminationStatus, 0, "\(app): \(msg)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        #else
        throw XCTSkip("macOS only")
        #endif
    }

    // MARK: LAB-2053 · only the helpers using a lot

    private func proc(_ pid: Int32, _ kind: String, mb: UInt64 = 0, bytes: UInt64? = nil, cpu: Double? = 0) -> MacProc {
        MacProc(pid: pid, ppid: 900, name: "Google Chrome Helper", path: "/x", kind: kind, footprint: bytes ?? (mb << 20), cpu: cpu, endable: true)
    }

    func test_LAB2053_bigThresholds() {
        let now = Date()
        XCTAssertEqual(BrowserTabs.bigBytes, 262_144_000)
        let procs = [proc(1, "GPU", bytes: 262_144_000),            // exactly 250 MB: not over
                     proc(2, "Network", bytes: 262_144_001),       // just over
                     proc(3, "Storage", mb: 240, cpu: 9),          // under both
                     proc(4, "Audio", mb: 10, cpu: 10),            // exactly 10 %: not over
                     proc(5, "Utility", mb: 10, cpu: 10.1),        // just over
                     proc(6, "Utility", mb: 10, cpu: nil)]         // no CPU yet
        XCTAssertEqual(BrowserTabs.bigProcesses(procs, since: [:], now: now).map(\.pid), [2, 5])
        XCTAssertTrue(BrowserTabs.isBig(proc(7, "GPU", mb: 300)))
        XCTAssertTrue(BrowserTabs.isBig(proc(8, "GPU", mb: 10, cpu: 15)))
        XCTAssertFalse(BrowserTabs.isBig(proc(9, "GPU", mb: 240, cpu: 9)))
    }

    func test_LAB2053_renderersCountAndHeaviestFirstWithoutTheMainProcess() {
        let now = Date()
        let main = MacProc(pid: 900, ppid: 1, name: "Google Chrome", path: "/x", kind: "Browser", footprint: 900 << 20, cpu: 30)
        let procs = [main, proc(1, BrowserTabs.rendererKind, mb: 300), proc(2, "GPU", mb: 640), proc(3, BrowserTabs.rendererKind, mb: 20, cpu: 15)]
        XCTAssertEqual(BrowserTabs.bigProcesses(procs, since: [:], now: now, mainPid: 900).map(\.pid), [2, 1, 3])
        XCTAssertEqual(BrowserTabs.bigProcesses(procs, since: [:], now: now).map(\.pid), [2, 1, 3], "the Browser kind is never a helper")
    }

    func test_LAB2053_heldThirtySecondsAfterDroppingBelow() {
        let t0 = Date()
        var since = BrowserTabs.bigSeen([proc(1, "GPU", mb: 300)], since: [:], now: t0)
        XCTAssertEqual(since[1], t0)
        // It drops below both lines: still listed for 30 s, then gone.
        let small = [proc(1, "GPU", mb: 100)]
        since = BrowserTabs.bigSeen(small, since: since, now: t0.addingTimeInterval(10))
        XCTAssertEqual(since[1], t0, "the stamp is when it was last over a line")
        XCTAssertEqual(BrowserTabs.bigProcesses(small, since: since, now: t0.addingTimeInterval(10)).map(\.pid), [1])
        XCTAssertEqual(BrowserTabs.bigProcesses(small, since: since, now: t0.addingTimeInterval(30)).map(\.pid), [1])
        XCTAssertEqual(BrowserTabs.bigProcesses(small, since: since, now: t0.addingTimeInterval(31)).map(\.pid), [])
        XCTAssertNil(BrowserTabs.bigSeen(small, since: since, now: t0.addingTimeInterval(31))[1])
        XCTAssertTrue(BrowserTabs.bigSeen([], since: since, now: t0.addingTimeInterval(1)).isEmpty, "a process that is gone drops")
    }

    // MARK: LAB-2054 / LAB-2060 · closing tabs and windows

    let chromeTab = BrowserTab(windowId: "1201", index: 3, tabId: "456", active: false, url: "https://example.com/a?b=\"c\"\\d", title: "A")

    func test_LAB2054_closeScriptsNeverLaunchTheBrowser() {
        for s in [BrowserTabs.closeTabScript(app: "Google Chrome", family: .chromium, tab: chromeTab),
                  BrowserTabs.closeTabScript(app: "Safari", family: .safari, tab: chromeTab),
                  BrowserTabs.closeWindowScript(app: "Google Chrome", windowId: "1201", tabs: 3)] {
            XCTAssertTrue(s.hasPrefix("if application \"") && s.components(separatedBy: "\n")[0].hasSuffix("is not running then return \"gone\""), s)
            XCTAssertFalse(s.contains("activate"), "closing never brings the browser forward or launches it")
            XCTAssertFalse(s.contains("execute javascript"), "no JavaScript from Apple Events")
        }
    }

    func test_LAB2054_closeScriptsQuoteAppNamesAndAddressesSafely() {
        let s = BrowserTabs.closeTabScript(app: "Odd \"Name\" \\ App", family: .chromium, tab: chromeTab)
        XCTAssertTrue(s.contains("application \"Odd \\\"Name\\\" \\\\ App\""), s)
        XCTAssertTrue(s.contains("is not \"https://example.com/a?b=\\\"c\\\"\\\\d\" then return \"changed\""), s)
        XCTAssertEqual(BrowserTabs.quoted("Brave Browser"), "\"Brave Browser\"")
        XCTAssertTrue(BrowserTabs.closeWindowScript(app: "Brave Browser", windowId: "7", tabs: 2).contains("application \"Brave Browser\""))
    }

    func test_LAB2054_closeTabGuardsTheAddressAndTheId() {
        let s = BrowserTabs.closeTabScript(app: "Google Chrome", family: .chromium, tab: chromeTab)
        XCTAssertTrue(s.contains("set w to window id 1201"))
        XCTAssertTrue(s.contains("(every tab of w whose id is 456)"))
        XCTAssertTrue(s.contains("then return \"changed\""))
        XCTAssertTrue(s.contains("close t"))
        // The address check comes before the close.
        XCTAssertLessThan(s.range(of: "return \"changed\"")!.lowerBound, s.range(of: "close t")!.lowerBound)
    }

    func test_LAB2054_closeWindowGuardsTheTabCount() {
        let s = BrowserTabs.closeWindowScript(app: "Google Chrome", windowId: "1201", tabs: 14)
        XCTAssertTrue(s.contains("set n to count of tabs of w"))
        XCTAssertTrue(s.contains("if n is not 14 then return \"changed\""))
        XCTAssertLessThan(s.range(of: "is not 14")!.lowerBound, s.range(of: "close w")!.lowerBound)
        XCTAssertEqual(BrowserTabs.closeScript(app: "Google Chrome", family: .chromium, target: .window(id: "1201", number: 2, tabs: 14)), s)
    }

    func test_LAB2060_safariClosesByPositionGuardedByTheAddress() {
        let s = BrowserTabs.closeTabScript(app: "Safari", family: .safari, tab: chromeTab)
        XCTAssertTrue(s.contains("if (count of tabs of w) < 3 then return \"changed\""))
        XCTAssertTrue(s.contains("set u to URL of tab 3 of w"))
        XCTAssertTrue(s.contains("close tab 3 of w"))
        XCTAssertLessThan(s.range(of: "is not \"https")!.lowerBound, s.range(of: "close tab 3 of w")!.lowerBound)
    }

    func test_LAB2054_outcomesFromTheScriptsAnswer() {
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 0, output: "ok\n"), .closed)
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 0, output: "gone\n"), .gone)
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 0, output: "changed"), .changed)
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 124, output: "timed out after 10 s"), .timedOut)
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 1, output: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"), .notAllowed)
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 1, output: "execution error: boom (-2700)"), .failed("execution error: boom (-2700)"))
        XCTAssertEqual(BrowserTabs.closeOutcome(status: 0, output: ""), .failed("no answer"))
    }

    /// The flow against a stub runner: the script it was given, the timeout, and what came back. Never a real browser.
    func test_LAB2054_closeRunsTheScriptWithTheTimeoutThroughTheRunner() {
        final class Seen: @unchecked Sendable { var script = ""; var timeout: TimeInterval = 0 }
        let seen = Seen()
        let ok: BrowserTabs.ScriptRunner = { s, t in seen.script = s; seen.timeout = t; return (0, "ok\n") }
        XCTAssertEqual(BrowserTabs.close(app: "Google Chrome", family: .chromium, target: .tab(chromeTab), runner: ok), .closed)
        XCTAssertEqual(seen.script, BrowserTabs.closeTabScript(app: "Google Chrome", family: .chromium, tab: chromeTab))
        XCTAssertEqual(seen.timeout, 10)
        let hung: BrowserTabs.ScriptRunner = { _, t in (124, "timed out after \(Int(t)) s") }
        XCTAssertEqual(BrowserTabs.close(app: "Google Chrome", family: .chromium, target: .window(id: "1", number: 1, tabs: 3), runner: hung), .timedOut)
        let notRunning: BrowserTabs.ScriptRunner = { _, _ in (0, "gone") }
        XCTAssertEqual(BrowserTabs.close(app: "Safari", family: .safari, target: .tab(chromeTab), runner: notRunning), .gone)
        // A read-only browser never runs a script.
        let never: BrowserTabs.ScriptRunner = { _, _ in XCTFail("ran a script for a read-only browser"); return (0, "ok") }
        if case .failed = BrowserTabs.close(app: "Brave Browser", family: .chromium, target: .tab(chromeTab), runner: never) {} else { XCTFail() }
    }

    func test_LAB2060_whichBrowsersClose() {
        XCTAssertEqual(BrowserTabs.closeSupport(appName: "Google Chrome"), .closes)
        XCTAssertEqual(BrowserTabs.closeSupport(appName: "Google Chrome Canary"), .closes)
        XCTAssertEqual(BrowserTabs.closeSupport(appName: "Safari"), .closes)
        for app in ["Brave Browser", "Arc", "Microsoft Edge", "Vivaldi"] {
            guard case .readOnly(let why) = BrowserTabs.closeSupport(appName: app) else { return XCTFail(app) }
            XCTAssertTrue(why.contains(app))
        }
    }

    func test_LAB2054_windowAsksFromTwoTabsAndTheWords() {
        XCTAssertFalse(BrowserTabs.closeWindowAsks(tabs: 1))
        XCTAssertTrue(BrowserTabs.closeWindowAsks(tabs: 2))
        typealias C = BrowserTabs.CloseCopy
        XCTAssertEqual(C.confirmTitle(window: 2, app: "Google Chrome"), "Close window 2 of Google Chrome?")
        XCTAssertEqual(C.confirmMessage(tabs: 14, app: "Google Chrome"), "This closes its 14 tabs. Google Chrome can reopen the window with ⇧⌘T.")
        XCTAssertEqual(C.closed("Inbox", app: "Google Chrome"), "Closed \u{201C}Inbox\u{201D}. Reopen it in Google Chrome with ⇧⌘T.")
        XCTAssertEqual(C.timedOut("Google Chrome"), "Google Chrome did not answer in 10 s. It may be busy or hung.")
        XCTAssertEqual(C.changed, "That tab changed since the list was read. The list is fresh now; try again.")
        XCTAssertTrue(C.taskManager("Google Chrome").contains("To end one hung tab, use Google Chrome's Task Manager (⇧Esc) › End process"))
    }

    /// The close scripts compile against the real dictionaries (Chrome when installed; Safari always on macOS).
    func test_LAB2054_closeScriptsCompile() throws {
        #if os(macOS)
        let compiler = "/usr/bin/osacompile"
        guard FileManager.default.isExecutableFile(atPath: compiler) else { throw XCTSkip("no osacompile") }
        var checked = 0
        for (app, fam) in [("Google Chrome", BrowserTabs.Family.chromium), ("Safari", .safari)]
        where FileManager.default.fileExists(atPath: "/Applications/\(app).app") || app == "Safari" {
            for script in [BrowserTabs.closeTabScript(app: app, family: fam, tab: chromeTab),
                           BrowserTabs.closeWindowScript(app: app, windowId: "1201", tabs: 3)] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: compiler)
                p.arguments = ["-o", NSTemporaryDirectory() + "oneroof-browser-close-\(getpid()).scpt", "-e", script]
                let err = Pipe(); p.standardError = err
                try p.run(); p.waitUntilExit()
                let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                XCTAssertEqual(p.terminationStatus, 0, "\(app): \(msg)\n\(script)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        #else
        throw XCTSkip("macOS only")
        #endif
    }
}
