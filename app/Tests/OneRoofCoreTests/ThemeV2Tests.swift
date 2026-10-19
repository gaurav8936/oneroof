import XCTest
@testable import OneRoofCore

/// APPEARANCE §6: every text/fill pair the v2 views use, in all three themes.
final class ThemeV2Tests: XCTestCase {
    let themes = ThemeName.panelChoices

    func testTextContrast() {
        for t in themes {
            let k = t.tokens
            for (bgName, bg) in [("window", k.window), ("sidebar", k.sidebar), ("surface", k.surface)] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, bg), 7, "\(t) text/\(bgName)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, bg), 4.5, "\(t) text2/\(bgName)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, bg), 3, "\(t) text3/\(bgName)")
            }
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.accentText, k.window), 4.5, "\(t) accentText")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.now, k.surface), 4.5, "\(t) now on surface")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.needsText, k.window), 4.5, "\(t) needs text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.onAccent, k.accent), 3, "\(t) button label on accent (large/bold)")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.diffAddText, k.diffAddFill.over(k.surface)), 4.5, "\(t) diff add")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.diffDelText, k.diffDelFill.over(k.surface)), 4.5, "\(t) diff del")
        }
    }

    func testStatusPillsAndDots() {
        for t in themes {
            let k = t.tokens
            for s in SessionStatus.allCases {
                let p = k.pill(s)
                let bg = p.fill ?? k.surface
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, bg.over(k.surface)), 4.5, "\(t) pill \(s)")
                if s.isLive || s == .needsYou {
                    for (n, panel) in [("window", k.window), ("sidebar", k.sidebar)] {
                        XCTAssertGreaterThanOrEqual(RGB.contrast(k.statusColor(s), panel), 3, "\(t) dot \(s)/\(n)")
                    }
                }
            }
            let sp = StatusPalette.scheduledPill(theme: t)
            XCTAssertGreaterThanOrEqual(RGB.contrast(sp.text, sp.fill!), 4.5, "\(t) scheduled pill")
        }
    }

    func testTerminalPalette() {
        for t in ThemeName.terminalChoices {
            let term = t.tokens.terminal
            XCTAssertEqual(term.ansi.count, 16)
            XCTAssertGreaterThanOrEqual(RGB.contrast(term.foreground, term.background), 12, "\(t) terminal fg")
            for i in Array(1...7) + Array(9...15) {
                XCTAssertGreaterThanOrEqual(RGB.contrast(term.ansi[i], term.background), 4.5, "\(t) ansi \(i)")
            }
        }
    }

    func testStickerInkReadsOnEveryTheme() {
        for t in themes {
            let k = t.tokens
            for s in Sticker.catalog {
                let c = k.sticker(s.pastel)
                XCTAssertGreaterThanOrEqual(RGB.contrast(c.ink, c.fill), 4.5, "\(t) sticker \(s.label)")
            }
        }
    }

    func testAgentMonogramsReadOnTheirFill() {
        for m in AgentMark.allCases {
            for dark in [false, true] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(m.ink(dark: dark), m.fill(dark: dark)), 4.5, "\(m) dark=\(dark)")
            }
        }
        XCTAssertEqual(AgentMark(agent: .claude, account: "Claude2"), .claude2)
        XCTAssertEqual(AgentMark(agent: .claude, account: nil), .claude1)
        XCTAssertEqual(AgentMark(agent: .agy, account: nil).mono, "AG")
    }

    func testGhosttyConfig() {
        let cfg = ThemeName.midnight.tokens.ghosttyConfig
        XCTAssertTrue(cfg.contains("background = #0b0b0d"))
        XCTAssertTrue(cfg.contains("palette = 15=#ffffff"))
    }

    func testAlphaComposite() {
        XCTAssertEqual(RGB(rgba: 0x0A84FF33).alpha, 0x33 / 255, accuracy: 0.001)
        XCTAssertEqual(RGB(0x000000, alpha: 0.5).over(RGB(0xFFFFFF)).hex, 0x808080)
    }
}

final class PanelThemesV2Tests: XCTestCase {
    func testDefaults() {
        let p = PanelThemes()
        XCTAssertEqual([p.sidebar, p.files, p.terminal, p.plan, p.centre], [.daylight, .daylight, .midnight, .graphite, .daylight])
    }

    func testV01SettingsMigrate() throws {
        let t = try JSONDecoder().decode(PanelThemes.self, from: Data(#"{"sidebar":"paper","terminal":"dark","plan":"dim"}"#.utf8))
        XCTAssertEqual(t.sidebar, .daylight, "Paper is retired")
        XCTAssertEqual(t.files, .daylight)
        XCTAssertEqual(t.terminal, .midnight)
        XCTAssertEqual(t.plan, .graphite)
        XCTAssertEqual(t.centre, .daylight)
        let b = try JSONDecoder().decode(PanelThemes.self, from: Data(#"{"sidebar":"blueprint","terminal":"blueprint","plan":"light"}"#.utf8))
        XCTAssertEqual(b.sidebar, .midnight, "Blueprint is terminal-only")
        XCTAssertEqual(b.terminal, .blueprint)
        XCTAssertEqual(b.plan, .daylight)
    }

    func testLoadPrefersV2KeyThenMigrates() throws {
        let d = UserDefaults(suiteName: "oneroof.test.\(UUID().uuidString)")!
        XCTAssertEqual(PanelThemes.load(d), PanelThemes())
        d.set(Data(#"{"sidebar":"dark","terminal":"light","plan":"dark"}"#.utf8), forKey: PanelThemes.legacyKey)
        XCTAssertEqual(PanelThemes.load(d).sidebar, .midnight)
        d.set(try JSONEncoder().encode(PanelThemes(sidebar: .graphite)), forKey: PanelThemes.storageKey)
        XCTAssertEqual(PanelThemes.load(d).sidebar, .graphite)
    }

    func testFollowAppearance() {
        let chosen = PanelThemes(sidebar: .daylight, files: .graphite, terminal: .midnight, plan: .daylight, centre: .daylight)
        XCTAssertEqual(chosen.forAppearance(systemDark: true, follow: false), chosen)
        XCTAssertEqual(chosen.forAppearance(systemDark: true, follow: true),
                       PanelThemes(sidebar: .midnight, files: .graphite, terminal: .midnight, plan: .midnight, centre: .midnight))
    }
}
