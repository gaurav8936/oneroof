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
        let out = rec("1201", 1, "11", false, "https://linear.app/zibajoon/project/x", "Project · Linear")
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
}
