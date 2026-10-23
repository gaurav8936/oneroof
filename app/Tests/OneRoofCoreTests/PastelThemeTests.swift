import XCTest
@testable import OneRoofCore

/// LAB-601: more pastel background choices.
final class PastelThemeTests: XCTestCase {
    func test_LAB601_pastelThemesAreOffered() {
        XCTAssertEqual(ThemeName.pastels, [.mint, .sky, .lavender, .peach])
        XCTAssertGreaterThanOrEqual(ThemeName.panelChoices.count, 7)
        for t in ThemeName.pastels {
            XCTAssertTrue(ThemeName.panelChoices.contains(t))
            XCTAssertTrue(ThemeName.terminalChoices.contains(t))
            XCTAssertFalse(t.isDark)
            XCTAssertEqual(t.darkTwin, .midnight, "follows macOS Dark Mode like Daylight")
            XCTAssertNotNil(t.pastel, "drawn from the same pastel palette as the window colours")
            XCTAssertTrue(Sticker.rowColors.contains(t.pastel!))
            XCTAssertNotEqual(t.tokens.sidebar, ThemeName.daylight.tokens.sidebar, "\(t) is tinted")
            XCTAssertEqual(t.tokens.name, t)
        }
        XCTAssertEqual(Set(ThemeName.pastels.map { $0.tokens.sidebar }).count, ThemeName.pastels.count)
        XCTAssertNil(ThemeName.daylight.pastel)
        // Menu tags are panel * 10 + allCases index.
        XCTAssertLessThan(ThemeName.allCases.count, 10)
        XCTAssertEqual(Array(ThemeName.allCases.prefix(4)), [.daylight, .graphite, .midnight, .blueprint], "existing indexes unchanged")
    }

    func test_LAB601_pastelChoiceIsSavedAndRead() throws {
        let p = PanelThemes(sidebar: .mint, files: .sky, terminal: .peach, plan: .graphite, centre: .lavender)
        let back = try JSONDecoder().decode(PanelThemes.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(p.forAppearance(systemDark: true, follow: true).sidebar, .midnight)
    }
}
