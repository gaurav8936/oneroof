import Foundation

/// LAB-799: a file opens as a tab beside the terminals, never in place of them. The centre's tab strip is
/// "Terminals" followed by one tab per open file; the terminals stay one click away while files are open.
public enum CentreTabs {
    /// Opening a path adds its tab once, at the end. Special views (Search, Review changes) are not files: no tab.
    public static func opening(_ path: String, in tabs: [String], isFile: Bool = true) -> [String] {
        guard isFile, !path.isEmpty, !tabs.contains(path) else { return tabs }
        return tabs + [path]
    }

    /// What the centre shows after closing `closing`: nil means the terminals. Closing a tab in the background
    /// changes nothing; closing the one in front shows its right neighbour, else its left, else the terminals.
    public static func showing(afterClosing closing: String, in tabs: [String], showing current: String?) -> String? {
        guard current == closing else { return current }
        guard let i = tabs.firstIndex(of: closing) else { return nil }
        let rest = tabs.filter { $0 != closing }
        if rest.isEmpty { return nil }
        return rest[min(i, rest.count - 1)]
    }
}
