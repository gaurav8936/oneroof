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

public enum BrowserTabs {
    public enum Family: Sendable { case chromium, safari }

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
