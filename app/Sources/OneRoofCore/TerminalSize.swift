import Foundation

/// LAB-606: `roofd attach` asks roofd for a redraw of the session's screen at its terminal's size. A libghostty surface
/// starts at a default size and only gets its real one when it is laid out in its pane, so the first size the attach
/// client read could be stale: roofd rebuilt the screen for, say, 17 rows, the pane then had 40, and the cursor landed
/// in the wrong row. The live output after that left a block of blank rows in the middle (or wrote over lines, or
/// pushed the top out of view). The client now waits until the size has stopped changing before it says hello.
public struct SizeSettle: Sendable {
    /// Equal reads in a row that count as settled.
    public let needed: Int
    public private(set) var cols: UInt16 = 0
    public private(set) var rows: UInt16 = 0
    private var same = 0

    public init(needed: Int = 3) { self.needed = needed }

    /// One read of the terminal's size; true once it has been the same `needed` times in a row.
    public mutating func read(cols c: UInt16, rows r: UInt16) -> Bool {
        guard c > 0, r > 0 else { same = 0; return false }
        if c == cols && r == rows { same += 1 } else { cols = c; rows = r; same = 1 }
        return same >= needed
    }

    /// How long the client waits at most (reads × interval), so a terminal that never settles still attaches.
    public static let maxReads = 12
    public static let intervalMicros: UInt32 = 25_000
}

/// LAB-657 (Wrap, now the Table view's terminal source, LAB-1286): a terminal's scrollback and screen as plain text
/// (libghostty already joins lines it soft-wrapped at the edge), tidied so a word-wrapping text view can lay it out
/// at the pane's width: trailing spaces off, no blank tail, runs of blank lines cut to one, the last `maxLines` kept.
public enum ReadingText {
    public static func prepare(_ raw: String, maxLines: Int = 5000) -> String {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out: [Substring] = []
        var blanks = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var l = line
            while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
            if l.isEmpty {
                blanks += 1
                if blanks > 1 || out.isEmpty { continue }
            } else { blanks = 0 }
            out.append(l)
        }
        while out.last?.isEmpty == true { out.removeLast() }
        if out.count > maxLines { out = Array(out.suffix(maxLines)) }
        return out.joined(separator: "\n")
    }
}
