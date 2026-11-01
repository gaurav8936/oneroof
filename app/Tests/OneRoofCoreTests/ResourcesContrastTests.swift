import XCTest
@testable import OneRoofCore

/// LAB-2052 · Resources: every text and mark pair on the page, per theme. Text ≥ 4.5:1 on the surface it sits on; marks
/// (bar fills, sparkline lines, pill edges, the warn tick) ≥ 3:1; a bar's track ≥ 1.5:1 against the card; hover ≥ 1.3:1.
/// Prints the contrast report (`swift test --filter ResourcesContrastTests 2>&1 | grep 'contrast '`).
final class ResourcesContrastTests: XCTestCase {
    /// Daylight, Graphite, Midnight (the spec's three) and the pastels (Mint Garden is the default look).
    let themes: [ThemeName] = [.daylight, .graphite, .midnight] + ThemeName.pastels

    private func check(_ theme: ThemeName, _ what: String, _ a: RGB, _ b: RGB, _ min: Double,
                       file: StaticString = #filePath, line: UInt = #line) {
        let r = RGB.contrast(a.over(b), b)
        print(String(format: "contrast %-9@ %-44@ %5.2f:1 (min %.1f) %@", theme.rawValue, what, r, min, r >= min ? "ok" : "LOW"))
        XCTAssertGreaterThanOrEqual(r, min, "\(theme.rawValue) · \(what): \(String(format: "%.2f", r)):1", file: file, line: line)
    }

    /// Text on the card, on the process panel and on a warning row.
    func test_LAB2052_textPairs() {
        for name in themes {
            let t = name.tokens, m = t.resourceMarks
            check(name, "text / card", t.text, m.card, 4.5)
            check(name, "text2 / card (pids, notes, footnote)", t.text2, m.card, 4.5)
            check(name, "text2 / panel (process panel, tab sites)", t.text2, m.panel, 4.5)
            check(name, "text / panel", t.text, m.panel, 4.5)
            check(name, "accentText / panel (All processes)", t.accentText, m.panel, 4.5)
            check(name, "text / now tint (warning row name)", t.text, m.nowTint, 4.5)
            check(name, "text2 / now tint (warning row note)", t.text2, m.nowTint, 4.5)
            check(name, "nowText / now tint (amount, ●)", m.nowText, m.nowTint, 4.5)
            check(name, "warn / card (This Mac under pressure)", m.warn, m.card, 4.5)
            check(name, "near / card (near the limit)", m.near, m.card, 4.5)
            check(name, "needsText / panel (could not close)", t.needsText, m.panel, 4.5)
        }
    }

    /// Bars: the fill against its track and the card; the track against the card; the warn tick.
    func test_LAB2052_barsAndTicks() {
        for name in themes {
            let m = name.tokens.resourceMarks
            check(name, "track / card", m.track, m.card, 1.5)
            for (label, fill) in [("bar", m.bar), ("warn", m.warn), ("near", m.near)] {
                check(name, "\(label) fill / track", fill, m.track, 3)
                check(name, "\(label) fill / card", fill, m.card, 3)
            }
            check(name, "warn tick / card", m.tick, m.card, 3)
            check(name, "warn tick / track", m.tick, m.track, 3)
            check(name, "warn bar (3 pt) / card", m.nowBar, m.card, 3)
            XCTAssertEqual(ResourceMarks.barHeight, 6)
        }
    }

    /// Sparkline line ≥ 3:1 against its card and against its own fill (0.22) under it; 2 pt.
    func test_LAB2052_sparklines() {
        XCTAssertEqual(ResourceMarks.sparkLine, 2)
        XCTAssertEqual(ResourceMarks.sparkFill, 0.22)
        for name in themes {
            let m = name.tokens.resourceMarks
            for (label, c) in [("memory/CPU line", m.bar), ("warn line", m.warn), ("near line", m.near)] {
                check(name, "\(label) / card", c, m.card, 3)
                check(name, "\(label) / its fill", c, c.opacity(ResourceMarks.sparkFill).over(m.card), 2.2)
            }
        }
    }

    /// Status pills on Resources: label ≥ 4.5:1 on its fill (or the card), and the strong edge ≥ 3:1 against the card.
    func test_LAB2052_statusPills() {
        for name in themes {
            let t = name.tokens, m = t.resourceMarks
            check(name, "pill edge / card", m.pillEdge, m.card, 3)
            for s in [SessionStatus.done, .idle, .running, .needsYou, .exited] {
                let p = t.pill(s)
                check(name, "\(StatusPalette.label(s)) pill label / fill", p.text, p.fill ?? m.card, 4.5)
            }
        }
    }

    /// Hover on a row ≥ 1.3:1 against the row (card rows and panel rows).
    func test_LAB2052_hover() {
        for name in themes {
            let t = name.tokens, m = t.resourceMarks
            check(name, "hover / card row", ResourceMarks.hover(over: m.card, dark: t.isDark), m.card, 1.3)
            check(name, "hover / panel row", ResourceMarks.hover(over: m.panel, dark: t.isDark), m.panel, 1.3)
            // Text on a hovered row still reads.
            check(name, "text2 / hovered panel row", t.text2, ResourceMarks.hover(over: m.panel, dark: t.isDark), 4.5)
        }
    }

    /// The front-tab ● and the ✕ on the panel are marks (≥ 3:1).
    func test_LAB2054_tabRowMarks() {
        for name in themes {
            let t = name.tokens, m = t.resourceMarks
            check(name, "front-tab ● (accent) / panel", t.accent, m.panel, 3)
            check(name, "✕ (text2) / hovered panel row", t.text2, ResourceMarks.hover(over: m.panel, dark: t.isDark), 3)
        }
    }
}
