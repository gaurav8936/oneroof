import XCTest
@testable import OneRoofCore

/// LAB-509 / LAB-590: a bold, editable window name and a per-window colour accent.
final class WindowAccentTests: XCTestCase {
    func test_LAB509_windowNameIsCleaned() {
        XCTAssertEqual(WindowName.clean("  Labs  "), "Labs")
        XCTAssertEqual(WindowName.clean("One\n  Roof"), "One Roof")
        XCTAssertNil(WindowName.clean("   \n "), "an empty name keeps the old one")
        XCTAssertEqual(WindowName.clean(String(repeating: "x", count: 80))?.count, WindowName.maxLength)
    }

    func test_LAB590_noColourMeansNoAccent() {
        let k = ThemeName.daylight.tokens
        XCTAssertNil(WindowAccent(named: nil, on: k), "unset: the toolbar looks as before")
        XCTAssertNil(WindowAccent(named: "no-such-colour", on: k))
        XCTAssertNotNil(WindowAccent(named: "mint", on: k))
    }

    func test_LAB590_accentReadsOnEveryTheme() {
        for th in ThemeName.panelChoices {
            let k = th.tokens
            for p in Sticker.rowColors {
                let a = WindowAccent(p, on: k)
                XCTAssertNotEqual(a.band, k.toolbar, "\(th) \(p.name) band is tinted")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, a.band), 7, "\(th) \(p.name) text")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, a.band), 4.5, "\(th) \(p.name) text2")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, a.band), 3, "\(th) \(p.name) text3")
                XCTAssertGreaterThanOrEqual(RGB.contrast(a.ink, a.band), 4.5, "\(th) \(p.name) window name")
            }
        }
    }

    func test_LAB590_windowsLookDistinct() {
        for th in [ThemeName.daylight, .midnight] {
            let bands = Sticker.rowColors.map { WindowAccent($0, on: th.tokens).band }
            XCTAssertEqual(Set(bands).count, bands.count, "\(th): every colour gives its own band")
        }
    }
}
