import XCTest
@testable import OneRoofCore

/// One Roof 1.x v2 window models (LAB-ONEROOF-UI-REDESIGN M0.5): looks, the Focus ladder, places, layouts.
final class LookTests: XCTestCase {
    func testLooksMatchTheHandoverTable() {
        XCTAssertEqual(Look.skyStudio.panelThemes, PanelThemes(sidebar: .sky, files: .sky, terminal: .graphite, plan: .daylight, centre: .sky))
        XCTAssertEqual(Look.mintGarden.panelThemes.terminal, .midnight)
        XCTAssertEqual(Look.lavenderDusk.panelThemes.terminal, .midnight)
        XCTAssertEqual(Look.peachPaper.panelThemes.terminal, .graphite)
        XCTAssertEqual(Look.daylight.panelThemes, PanelThemes(sidebar: .daylight, files: .daylight, terminal: .daylight, plan: .daylight, centre: .daylight))
        XCTAssertEqual(Look.midnight.panelThemes.plan, .midnight)
        XCTAssertEqual(Look.allCases.count, 6)
    }

    func testMatchingFindsTheLookOrNil() {
        for l in Look.allCases { XCTAssertEqual(Look.matching(l.panelThemes), l) }
        XCTAssertNil(Look.matching(PanelThemes(sidebar: .mint, files: .sky, terminal: .blueprint, plan: .peach, centre: .daylight)))
    }

    /// Every look keeps body text ≥ 4.5:1 on each plane it paints (TEST_CHECKLIST: ThemeV2Tests extended).
    func testEveryLookKeepsTextReadable() {
        for l in Look.allCases {
            let t = l.panelThemes
            for (name, theme) in [("rail", l.rail), ("sessions", t.sidebar), ("plan", t.plan), ("centre", t.centre)] {
                let k = theme.tokens
                for (bgName, bg) in [("control", k.control), ("sidebar", k.sidebar), ("window", k.window), ("surface", k.surface)] {
                    XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, bg), 4.5, "\(l) \(name) text on \(bgName)")
                }
            }
            // The terminal card: its text on its own surface and header, and the terminal's own colours.
            let term = t.terminal.tokens
            XCTAssertGreaterThanOrEqual(RGB.contrast(term.text, term.surface), 4.5, "\(l) terminal card text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(term.text, term.surface2), 4.5, "\(l) terminal card header text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(term.terminal.foreground, term.terminal.background), 4.5, "\(l) terminal text")
        }
    }

    func testFocusLadderRoundTrip() {
        for start in FocusStep.allCases {
            var s = start
            for _ in 0..<3 { s = s.next }
            XCTAssertEqual(s, .focus)
            for _ in 0..<3 { s = s.previous }
            XCTAssertEqual(s, .full)
        }
        XCTAssertEqual(FocusStep.sessions.next.next.previous.previous, .sessions)
    }

    func testFocusLadderPanels() {
        XCTAssertTrue(FocusStep.full.showsRail && FocusStep.full.showsInspector && FocusStep.full.showsDock)
        XCTAssertTrue(FocusStep.sessions.showsIconRow && FocusStep.sessions.showsDockLine && FocusStep.sessions.showsInspectorTab)
        XCTAssertTrue(FocusStep.wide.showsRail && FocusStep.wide.seatsInRail && !FocusStep.wide.showsDock)
        XCTAssertTrue(FocusStep.focus.showsAvatars && !FocusStep.focus.showsSessionColumn && !FocusStep.focus.showsDock)
    }

    func testPlacesOpenAtTheirDefaultStep() {
        XCTAssertEqual(Place.sessions.defaultStep, .sessions)
        for p in [Place.home, .needsYou, .work, .machine, .loops] { XCTAssertEqual(p.defaultStep, .full, "\(p)") }
        XCTAssertEqual(SessionLayout.grid.defaultStep, .wide)
        XCTAssertEqual(SessionLayout.wall.defaultStep, .wide)
        XCTAssertEqual(Place.allCases.map(\.controlKey), ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(Place.home.symbol, "house")
        XCTAssertEqual(Place.learn.symbol, "graduationcap")
    }

    func testSettingsKeepUI2OffAndSkyStudioByDefault() throws {
        let s = AppSettings()
        XCTAssertFalse(s.ui2)
        XCTAssertEqual(s.look, .skyStudio)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))   // 0.5.2.9 settings without the keys
        XCTAssertFalse(old.ui2)
        XCTAssertNil(old.look, "settings from before 1.0.0 keep their own panel themes")
        var custom = AppSettings(); custom.look = nil; custom.ui2 = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        XCTAssertNil(back.look)
        XCTAssertTrue(back.ui2)
    }
}
