import Foundation

// LAB-554: Resources › This Mac lists a browser's renderers as "Tab or site" with no name, because macOS does not tell
// other apps which tab a renderer process belongs to. The browser itself knows its tabs: asked over Apple Events (the
// same scripting Chrome, Brave, Edge, Arc, Vivaldi and Safari document), it gives each tab's title and address. One Roof
// asks only when the owner presses "Show tab names" (macOS asks once whether One Roof may control the browser), and
// shows the tabs grouped by site. Memory per tab stays in the browser's own Task Manager. Pure here; the app runs the
// script with /usr/bin/osascript.

/// One open tab in a browser window.
public struct BrowserTab: Equatable, Sendable, Identifiable {
    /// The window's scripting id (stable while the window is open, unlike its index, which follows the window order).
    public var windowId: String
    /// 1-based position in its window.
    public var index: Int
    /// The tab's scripting id (Chromium browsers), else its index (Safari).
    public var tabId: String
    /// The tab in front in its window.
    public var active: Bool
    public var url: String
    public var title: String
    public var id: String { windowId + "/" + tabId }
    public init(windowId: String, index: Int, tabId: String, active: Bool, url: String, title: String) {
        self.windowId = windowId; self.index = index; self.tabId = tabId; self.active = active; self.url = url; self.title = title
    }
    public var site: String { BrowserTabs.site(url) }
}

/// The tabs open on one site.
public struct BrowserSite: Equatable, Sendable, Identifiable {
    public var site: String
    public var tabs: [BrowserTab]
    public var id: String { site }
}

/// The tabs of one browser window (LAB-853: Chrome's tabs by window, as the owner sees them in Chrome).
public struct BrowserWindowTabs: Equatable, Sendable, Identifiable {
    public var windowId: String
    /// 1-based, in the order the browser listed its windows (front window first).
    public var number: Int
    public var tabs: [BrowserTab]
    public var id: String { windowId }
    /// The window's front tab (what its title bar shows).
    public var front: BrowserTab? { tabs.first(where: \.active) }
}

public enum BrowserTabs {
    public enum Family: Sendable { case chromium, safari }

    /// The kind MacResources gives a browser's renderer processes (one per tab or site, unnamed by macOS).
    public static let rendererKind = "Tab or site"

    /// Tabs grouped by window, windows and tabs in the browser's order.
    public static func windows(_ tabs: [BrowserTab]) -> [BrowserWindowTabs] {
        var out: [BrowserWindowTabs] = []
        for t in tabs {
            if let i = out.firstIndex(where: { $0.windowId == t.windowId }) { out[i].tabs.append(t) }
            else { out.append(BrowserWindowTabs(windowId: t.windowId, number: out.count + 1, tabs: [t])) }
        }
        return out.map { w in var w = w; w.tabs.sort { $0.index < $1.index }; return w }
    }

    /// The renderer ("Tab or site") processes of an app: how many, and their memory together.
    public static func renderers(_ procs: [MacProc]) -> (count: Int, bytes: UInt64) {
        procs.filter { $0.kind == rendererKind }.reduce((0, 0)) { ($0.0 + 1, $0.1 + $1.footprint) }
    }

    /// May One Roof read this browser's tabs? Asked of macOS without prompting (AEDeterminePermissionToAutomateTarget
    /// with askUserIfNeeded = false), so the page can say so before the owner presses anything.
    public enum Permission: Equatable, Sendable {
        case granted
        /// macOS has not asked the owner yet: the first read asks.
        case notAsked
        /// The owner said no (System Settings › Privacy & Security › Automation).
        case denied
        case notRunning
        case unknown(Int32)
    }

    /// The OSStatus from AEDeterminePermissionToAutomateTarget → Permission.
    public static func permission(status: Int32) -> Permission {
        switch status {
        case 0: return .granted
        case -1744: return .notAsked      // errAEEventWouldRequireUserConsent
        case -1743: return .denied        // errAEEventNotPermitted
        case -600: return .notRunning     // procNotFound
        default: return .unknown(status)
        }
    }

    /// Browsers whose tabs can be listed, by app name (as Resources names the group).
    public static func family(appName: String) -> Family? {
        let chromium = ["Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge", "Arc", "Vivaldi", "Opera"]
        if chromium.contains(where: { appName == $0 || appName.hasPrefix($0 + " ") }) { return .chromium }
        if appName == "Safari" || appName == "Safari Technology Preview" { return .safari }
        return nil
    }

    /// Field and record separators in the script's output (titles may hold tabs and new lines, never these).
    static let fieldSep = "\u{1F}", recordSep = "\u{1E}"

    /// AppleScript that lists every tab of `app` as records of: window id, tab index, tab id, active, URL, title.
    /// It never launches the browser (it answers nothing when the browser is not running).
    public static func listScript(app: String, family: Family) -> String {
        let a = quoted(app)
        let body: String
        switch family {
        case .chromium:
            body = """
                repeat with w in windows
                    try
                        set wid to id of w
                        set ai to active tab index of w
                        set ids to id of every tab of w
                        set urls to URL of every tab of w
                        set names to title of every tab of w
                        repeat with i from 1 to count of urls
                            set out to out & wid & fs & i & fs & (item i of ids) & fs & (i = ai) & fs & (item i of urls) & fs & (item i of names) & rs
                        end repeat
                    end try
                end repeat
            """
        case .safari:
            body = """
                repeat with w in windows
                    try
                        set wid to id of w
                        set ai to index of current tab of w
                        set urls to URL of every tab of w
                        set names to name of every tab of w
                        repeat with i from 1 to count of urls
                            set u to item i of urls
                            if u is missing value then set u to ""
                            set out to out & wid & fs & i & fs & i & fs & (i = ai) & fs & u & fs & (item i of names) & rs
                        end repeat
                    end try
                end repeat
            """
        }
        return """
        if application \(a) is not running then return ""
        set fs to character id 31
        set rs to character id 30
        set out to ""
        tell application \(a)
        \(body)
        end tell
        return out
        """
    }

    /// AppleScript that brings one tab to the front of its window and the window to the front.
    public static func showScript(app: String, family: Family, tab: BrowserTab) -> String {
        let a = quoted(app)
        let wid = Int(tab.windowId) ?? 0
        let select: String
        switch family {
        case .chromium:
            let tid = Int(tab.tabId) ?? 0
            select = """
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if id of t is \(tid) then set active tab index of w to i
                end repeat
            """
        case .safari:
            select = "    set current tab of w to tab \(tab.index) of w"
        }
        return """
        if application \(a) is not running then return
        tell application \(a)
            set w to window id \(wid)
        \(select)
            set index of w to 1
            activate
        end tell
        """
    }

    /// Records from `listScript` → tabs, in window and tab order. Malformed records are skipped.
    public static func parse(_ out: String) -> [BrowserTab] {
        out.components(separatedBy: recordSep).compactMap { r in
            let f = r.trimmingCharacters(in: .newlines).components(separatedBy: fieldSep)
            guard f.count >= 6, let i = Int(f[1]) else { return nil }
            let title = f[5...].joined(separator: " ")
            return BrowserTab(windowId: f[0], index: i, tabId: f[2], active: f[3] == "true", url: f[4], title: title)
        }
    }

    /// Tabs grouped by site: the most tabs first, then by name.
    public static func sites(_ tabs: [BrowserTab]) -> [BrowserSite] {
        Dictionary(grouping: tabs, by: \.site).map { BrowserSite(site: $0.key, tabs: $0.value) }
            .sorted { a, b in a.tabs.count != b.tabs.count ? a.tabs.count > b.tabs.count : a.site < b.site }
    }

    /// "https://www.github.com/x/y" → "github.com"; browser pages ("chrome://settings") → "Browser pages"; files →
    /// "Files on this Mac"; anything without a host → the address as it is.
    public static func site(_ url: String) -> String {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased() else { return url.isEmpty ? "Blank tab" : url }
        if scheme == "file" { return "Files on this Mac" }
        if ["chrome", "edge", "brave", "vivaldi", "arc", "about", "chrome-extension", "favorites", "opera"].contains(scheme) {
            return url.hasPrefix("about:blank") ? "Blank tab" : "Browser pages"
        }
        guard var h = c.host?.lowercased(), !h.isEmpty else { return url }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// Why a listing failed, from osascript's exit status and error text.
    public enum Failure: Error, Equatable, Sendable {
        /// The owner said no to "One Roof wants to control …", or has not been asked yet (-1743).
        case notAllowed
        case failed(String)
    }

    public static func failure(status: Int32, stderr: String) -> Failure? {
        guard status != 0 else { return nil }
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authori") { return .notAllowed }
        let line = stderr.split(separator: "\n").first.map(String.init) ?? "osascript exited \(status)"
        return .failed(line.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Big helpers (LAB-2053)

    /// A browser's helper or renderer counts as "using a lot" above either line (owner, 2026-10-31).
    public static let bigBytes: UInt64 = 250 * 1_048_576          // 262,144,000 bytes, "250 MB" as ResourceFormat shows it
    public static let bigCPU: Double = 10                          // percent, as the row shows it
    /// A process that drops below both lines stays listed this long, so the list does not flicker.
    public static let bigHold: TimeInterval = 30

    /// Over 250 MB or over 10 % CPU (exactly on a line is not over it).
    public static func isBig(_ p: MacProc) -> Bool { p.footprint > bigBytes || (p.cpu ?? 0) > bigCPU }

    /// The helpers and renderers to show under "Using a lot": over a line now, or over one within the last 30 s
    /// (`since`: when each pid was last seen over a line). The browser's own main process is not a helper (Quit is on
    /// the app row). Heaviest first.
    public static func bigProcesses(_ procs: [MacProc], since: [Int32: Date], now: Date, mainPid: Int32? = nil) -> [MacProc] {
        procs.filter { p in
            guard p.pid != mainPid, p.kind != "Browser" else { return false }
            if isBig(p) { return true }
            if let t = since[p.pid] { return now.timeIntervalSince(t) <= bigHold }
            return false
        }
        .sorted { a, b in a.footprint != b.footprint ? a.footprint > b.footprint : a.pid < b.pid }
    }

    /// `since` after a new sample: every pid over a line now is stamped `now`; pids that are gone or past the hold drop.
    public static func bigSeen(_ procs: [MacProc], since: [Int32: Date], now: Date) -> [Int32: Date] {
        var out: [Int32: Date] = [:]
        for p in procs {
            if isBig(p) { out[p.pid] = now }
            else if let t = since[p.pid], now.timeIntervalSince(t) <= bigHold { out[p.pid] = t }
        }
        return out
    }

    // MARK: Closing tabs and windows (LAB-2054 Chrome, LAB-2060 Safari)

    /// Can One Roof close this browser's tabs? Chrome (verified with `sdef`, the same Automation permission as reading)
    /// and Safari (closes by window id + position, guarded by the address). Brave and Arc stay read-only until they
    /// are installed on a test Mac (agent decision 2026-11-01, LAB-2060); Edge, Vivaldi, Opera are out of scope.
    public enum CloseSupport: Equatable, Sendable {
        case closes
        /// Tabs are listed, never closed; the reason is shown under the list.
        case readOnly(String)
    }

    public static func closeSupport(appName: String) -> CloseSupport {
        if appName == "Google Chrome" || appName.hasPrefix("Google Chrome ") { return .closes }
        if family(appName: appName) == .safari { return .closes }
        return .readOnly("Closing \(appName) tabs from One Roof comes later: it is not tested yet, so its tabs are listed only.")
    }

    /// What to close: one tab (by its id, or for Safari its position, guarded by its address) or a whole window (by its
    /// id, guarded by how many tabs it had when the list was read).
    public enum CloseTarget: Equatable, Sendable {
        case tab(BrowserTab)
        case window(id: String, number: Int, tabs: Int)
    }

    /// What a close script answered.
    public enum CloseOutcome: Equatable, Sendable {
        /// Closed.
        case closed
        /// Already closed (or the browser is not running): just refresh.
        case gone
        /// The tab moved or navigated, or the window gained or lost tabs since the list was read: nothing closed.
        case changed
        /// No answer in time: the browser may be busy or hung.
        case timedOut
        case notAllowed
        case failed(String)
    }

    /// Seconds a close may take before the browser counts as not answering.
    public static let closeTimeout: TimeInterval = 10

    /// AppleScript that closes one tab. Never launches the browser ("gone" when it is not running); closes only when
    /// the tab still shows the address that was read ("changed" otherwise). Answers ok · gone · changed.
    public static func closeTabScript(app: String, family: Family, tab: BrowserTab) -> String {
        let a = quoted(app), u = quoted(tab.url)
        let wid = Int(tab.windowId) ?? 0
        let body: String
        switch family {
        case .chromium:
            let tid = Int(tab.tabId) ?? 0
            body = """
                set ts to (every tab of w whose id is \(tid))
                if (count of ts) is 0 then return "gone"
                set t to item 1 of ts
                set u to URL of t
                if u is missing value then set u to ""
                if (u as text) is not \(u) then return "changed"
                close t
                return "ok"
            """
        case .safari:
            // Safari's tabs have no id: the tab at the position that was read, only if it still shows that address.
            body = """
                if (count of tabs of w) < \(tab.index) then return "changed"
                set u to URL of tab \(tab.index) of w
                if u is missing value then set u to ""
                if (u as text) is not \(u) then return "changed"
                close tab \(tab.index) of w
                return "ok"
            """
        }
        return """
        if application \(a) is not running then return "gone"
        tell application \(a)
            try
                set w to window id \(wid)
            on error
                return "gone"
            end try
        \(body)
        end tell
        """
    }

    /// AppleScript that closes a whole window, only when it still has the number of tabs that was read.
    public static func closeWindowScript(app: String, windowId: String, tabs: Int) -> String {
        let a = quoted(app)
        let wid = Int(windowId) ?? 0
        return """
        if application \(a) is not running then return "gone"
        tell application \(a)
            try
                set w to window id \(wid)
                set n to count of tabs of w
            on error
                return "gone"
            end try
            if n is not \(tabs) then return "changed"
            close w
            return "ok"
        end tell
        """
    }

    /// The script for a target.
    public static func closeScript(app: String, family: Family, target: CloseTarget) -> String {
        switch target {
        case .tab(let t): return closeTabScript(app: app, family: family, tab: t)
        case .window(let id, _, let n): return closeWindowScript(app: app, windowId: id, tabs: n)
        }
    }

    /// osascript's exit status and output → what happened. Status 124 is `Foundations.run`'s timeout.
    public static func closeOutcome(status: Int32, output: String) -> CloseOutcome {
        if status == 124 && output.hasPrefix("timed out") { return .timedOut }
        if let f = failure(status: status, stderr: output) {
            switch f {
            case .notAllowed: return .notAllowed
            case .failed(let why): return .failed(why)
            }
        }
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "ok": return .closed
        case "gone": return .gone
        case "changed": return .changed
        case let other: return .failed(other.isEmpty ? "no answer" : "unexpected answer \"\(other)\"")
        }
    }

    /// Runs a script with a timeout → (exit status, output). Tests pass a stub; the app runs /usr/bin/osascript.
    public typealias ScriptRunner = @Sendable (_ script: String, _ timeout: TimeInterval) -> (Int32, String)
    public static let osascript: ScriptRunner = { script, timeout in
        Foundations.run("/usr/bin/osascript", ["-e", script], timeout: timeout)
    }

    /// Close a tab or a window (call off the main thread). Never launches the browser.
    public static func close(app: String, family: Family, target: CloseTarget, runner: ScriptRunner = osascript,
                             timeout: TimeInterval = closeTimeout) -> CloseOutcome {
        if case .readOnly = closeSupport(appName: app) { return .failed("\(app) tabs can't be closed from One Roof yet") }
        let (status, out) = runner(closeScript(app: app, family: family, target: target), timeout)
        return closeOutcome(status: status, output: out)
    }

    /// A window with this many tabs asks before closing (one tab closes at once: the browser can reopen it).
    public static func closeWindowAsks(tabs: Int) -> Bool { tabs >= 2 }

    /// The words around closing (LAB-2054), so the page and the tests say the same.
    public enum CloseCopy {
        public static func closed(_ title: String, app: String) -> String {
            "Closed \u{201C}\(title.isEmpty ? "Untitled tab" : title)\u{201D}. Reopen it in \(app) with ⇧⌘T."
        }
        public static func closedWindow(_ number: Int, tabs: Int, app: String) -> String {
            "Closed window \(number) (\(tabs) tab\(tabs == 1 ? "" : "s")). Reopen it in \(app) with ⇧⌘T."
        }
        public static let changed = "That tab changed since the list was read. The list is fresh now; try again."
        public static let windowChanged = "That window's tabs changed since the list was read. The list is fresh now; try again."
        public static func timedOut(_ app: String) -> String {
            "\(app) did not answer in \(Int(closeTimeout)) s. It may be busy or hung."
        }
        public static func failed(_ why: String) -> String { "Could not close the tab: \(why)" }
        public static func confirmTitle(window number: Int, app: String) -> String { "Close window \(number) of \(app)?" }
        public static func confirmMessage(tabs: Int, app: String) -> String {
            "This closes its \(tabs) tabs. \(app) can reopen the window with ⇧⌘T."
        }
        /// The ⓘ on the one-line Task Manager note.
        public static func taskManager(_ app: String) -> String {
            "\(app)'s own Task Manager (⇧Esc in \(app), or Window › Task Manager) lists each tab with its memory and can end it. "
            + "macOS does not tell other apps which process is which tab, so One Roof cannot show memory per tab or force-close one tab. "
            + "To end one hung tab, use \(app)'s Task Manager (⇧Esc) › End process: that tab shows as crashed until reloaded."
        }
    }

    // MARK: Running the scripts (call off the main thread)

    /// Every tab of `app`. The first time, macOS asks the owner whether One Roof may control the browser and the call
    /// waits for the answer, hence the long timeout.
    public static func list(app: String, family: Family, timeout: TimeInterval = 120) -> Result<[BrowserTab], Failure> {
        let (status, out) = Foundations.run("/usr/bin/osascript", ["-e", listScript(app: app, family: family)], timeout: timeout)
        if let f = failure(status: status, stderr: out) { return .failure(f) }
        return .success(parse(out))
    }

    /// Bring one tab forward. nil = done.
    public static func show(app: String, family: Family, tab: BrowserTab) -> Failure? {
        let (status, out) = Foundations.run("/usr/bin/osascript", ["-e", showScript(app: app, family: family, tab: tab)], timeout: 20)
        return failure(status: status, stderr: out)
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
