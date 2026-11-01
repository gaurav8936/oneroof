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
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, bg), 4.5, "\(t) text3/\(bgName) (LAB-2071: meta text is read)")
            }
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.accentText, k.window), 4.5, "\(t) accentText")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.now, k.surface), 4.5, "\(t) now on surface")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.needsText, k.window), 4.5, "\(t) needs text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.onAccent, k.accent), 3, "\(t) button label on accent (large/bold)")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.diffAddText, k.diffAddFill.over(k.surface)), 4.5, "\(t) diff add")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.diffDelText, k.diffDelFill.over(k.surface)), 4.5, "\(t) diff del")
        }
    }

    /// LAB-1939 · LAB-1951: the loop views, the Scroll page and Needs you put body text (text, text2, the needs red,
    /// links) on the page, on cards (surface, or surface2 in light themes) and on rows: 4.5:1 in all three themes.
    /// Help sentences there use text2 (text3 is 3.25:1 on a Daylight card: meta only). Graphite's red was 4.02:1 on a card.
    func test_LAB1951_bodyTextOnPagesAndCards() {
        for t in [ThemeName.daylight, .graphite, .midnight] {
            let k = t.tokens
            for (bn, bg) in [("window", k.window), ("surface", k.surface), ("surface2", k.surface2)] {
                for (fn, fg) in [("text", k.text), ("text2", k.text2), ("needsText", k.needsText), ("accentText", k.accentText)] {
                    XCTAssertGreaterThanOrEqual(RGB.contrast(fg, bg), 4.5, "\(t) \(fn)/\(bn)")
                }
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, bg), 3, "\(t) text3 (meta)/\(bn)")
            }
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

    /// LAB-2045 · History: every kind's word on its row fill ≥ 4.5:1 (an error on its tinted fill, your answer on the
    /// selection fill, the rest on the session card), and every bar ≥ 3:1 against the card, in all three themes.
    /// LAB-2048 · the Action log's answer glyph colours on its card and on a hovered (selection) row.
    func test_LAB2045_historyKindColoursOnTheirFillsAndBars() {
        for t in [ThemeName.daylight, .graphite, .midnight] {
            let k = t.tokens
            for kind in ScrollEntry.Kind.allCases {
                let st = kind.style
                let fill = st.treatment == .errorFill ? k.historyErrorFill : k.card
                XCTAssertGreaterThanOrEqual(RGB.contrast(st.colour.rgb(k), fill), 4.5, "\(t) \(kind) word on its fill")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, fill), 4.5, "\(t) \(kind) body text on its fill")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, fill), 4.5, "\(t) \(kind) date on its fill")
                switch st.treatment {
                case .bar(let c): XCTAssertGreaterThanOrEqual(RGB.contrast(c.bar(k), k.card), 3, "\(t) \(kind) bar vs card")
                case .errorFill: XCTAssertGreaterThanOrEqual(RGB.contrast(k.needsText, k.card), 3, "\(t) error bar vs card")
                default: break
                }
            }
            let sel = k.selection.over(k.card)
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, sel), 4.5, "\(t) You row text on selection")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, sel), 4.5, "\(t) You row date on selection")
            for a in ActionLogAnswer.allCases {
                XCTAssertGreaterThanOrEqual(RGB.contrast(a.colour.rgb(k), k.card), 4.5, "\(t) action log \(a) on card")
                XCTAssertGreaterThanOrEqual(RGB.contrast(a.colour.rgb(k), k.rowHover), 4.5, "\(t) action log \(a) on a hovered row")
            }
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.separatorStrong, k.window), 3, "\(t) card edge vs window")
        }
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

/// LAB-2071: the shared contrast pass. Meta text (text3) is read, so it gets body contrast on every page, card and row
/// background; strong edges (card and control borders) reach the 3:1 that UI parts need; hairlines stay visible.
final class ContrastPassTests: XCTestCase {
    func test_LAB2071_metaTextEdgesAndHairlines() {
        for t in ThemeName.panelChoices {
            let k = t.tokens
            for (bn, bg) in [("window", k.window), ("toolbar", k.toolbar), ("sidebar", k.sidebar), ("surface", k.surface), ("surface2", k.surface2)] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text3, bg), 4.5, "\(t) text3/\(bn)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, bg), 4.5, "\(t) text2/\(bn)")
            }
            for (bn, bg) in [("window", k.window), ("sidebar", k.sidebar), ("surface", k.surface), ("surface2", k.surface2)] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.separatorStrong, bg), 3, "\(t) strong edge/\(bn)")
            }
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.separator, k.surface), 1.35, "\(t) hairline/surface")
        }
    }
}

/// LAB-2039 · LAB-2049: the places say what they hold.
final class PlaceNamesTests: XCTestCase {
    func test_LAB2039_LAB2049_placeTitles() {
        XCTAssertEqual(Place.machine.title, "Resources")
        XCTAssertEqual(Place.work.title, "Projects")
        XCTAssertFalse(Place.allCases.map(\.title).contains("Machine"))
        XCTAssertFalse(Place.allCases.map(\.title).contains("Work"))
    }
}

/// LAB-2039 · LAB-2049 · LAB-2072: shortcuts the owner set under the old place names keep working.
final class PlaceRenameShortcutTests: XCTestCase {
    func test_LAB2039_machineShortcutReachesResources() {
        XCTAssertEqual(MenuRenames.carry(["Machine": "⌘J"])["Resources"], "⌘J")
    }
    func test_LAB2049_workShortcutReachesProjects() {
        XCTAssertEqual(MenuRenames.carry(["Work": "⌘J"])["Projects"], "⌘J")
        XCTAssertEqual(MenuRenames.carry(["Work: Projects and Roadmap": "⌘J"])["Projects"], "⌘J", "through the chain")
    }
    func test_LAB2072_evalsShortcutReachesDraftTitle() {
        XCTAssertEqual(MenuRenames.carry(["Evals": "⌘J"])[EvalsDraft.menuTitle], "⌘J")
    }
}

/// QA M4: an agent's status line is never shown as a finished turn's message.
final class StatusLineTests: XCTestCase {
    func test_statusLineIsChrome() {
        XCTAssertTrue(TerminalText.isStatusLine("[Claude1] you@example.edu · Max 20x · 7d 9%"))
        XCTAssertTrue(TerminalText.isChrome("  [C2] me@host · Pro · 5h 24%"))
        XCTAssertFalse(TerminalText.isStatusLine("I've filed three bugs · all in Backlog"))
        XCTAssertFalse(TerminalText.isStatusLine("[note] tests pass · 100% of them run"), "a sentence, not a status line: has words after")
    }
}

/// Final QA: the Learn note never repeats the same range or lists fewer ranges than it names.
final class LearnRangesPhraseTests: XCTestCase {
    func test_rangesPhrase() {
        XCTAssertEqual(EvalLessonExamples.rangesPhrase(["34–100 %", "34–100 %", "34–100 %"]), "each one's range is 34–100 %")
        XCTAssertEqual(EvalLessonExamples.rangesPhrase(["34–100 %", "12–60 %", "34–100 %"]), "their ranges are 34–100 % and 12–60 %")
    }
}
