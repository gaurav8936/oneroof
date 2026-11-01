import XCTest
@testable import OneRoofCore

/// LAB-2056: every token pair the Loops screens use (Kinds, a family's page, the pop-out, Activity) passes in each
/// panel theme: text 4.5:1 on its surface, chip and card edges, disabled labels and health bars 3:1.
final class LoopsContrastTests: XCTestCase {
    func test_LAB2056_textOnCardsAndPage() {
        for theme in ThemeName.panelChoices {
            let k = theme.tokens
            for (bn, bg) in [("card", k.surface), ("page", k.window)] {
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, bg), 4.5, "\(theme) body text2/\(bn)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, bg), 4.5, "\(theme) text/\(bn)")
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.accentText, bg), 4.5, "\(theme) links (Open ›, ‹ Loops)/\(bn)")
            }
        }
    }

    func test_LAB2056_cardEdges() {
        for theme in ThemeName.panelChoices {
            let k = theme.tokens
            XCTAssertGreaterThanOrEqual(RGB.contrast(LoopLook.cardEdge(theme), k.window), 3, "\(theme) card edge/page")
            XCTAssertGreaterThanOrEqual(RGB.contrast(LoopLook.cardEdge(theme), k.surface), 3, "\(theme) card edge/card")
        }
    }

    func test_LAB2056_stateChips() {
        for theme in ThemeName.panelChoices {
            let k = theme.tokens
            for s in LoopState.allCases {
                let p = LoopLook.pill(s, theme: theme)
                let fill = p.fill ?? k.surface
                XCTAssertGreaterThanOrEqual(RGB.contrast(p.text, fill), 4.5, "\(theme) \(s) chip label/fill")
            }
            let off = LoopLook.pill(.stopped, theme: theme)
            guard case .solid(let edge) = off.edge else { return XCTFail("\(theme) Off chip has a solid edge") }
            XCTAssertGreaterThanOrEqual(RGB.contrast(edge, k.surface), 3, "\(theme) Off chip edge/card")
        }
    }

    func test_LAB2056_loopNameChips() {
        for theme in ThemeName.panelChoices {
            let k = theme.tokens
            for mine in [true, false] {
                let c = LoopLook.chip(mine: mine, theme: theme)
                XCTAssertGreaterThanOrEqual(RGB.contrast(c.text, c.fill ?? k.surface), 4.5, "\(theme) chip text (mine \(mine))")
                XCTAssertGreaterThanOrEqual(RGB.contrast(c.edge, k.surface), 3, "\(theme) chip edge/card (mine \(mine))")
            }
            let filled = LoopLook.chip(mine: true, theme: theme).fill ?? k.surface
            XCTAssertGreaterThanOrEqual(RGB.contrast(filled, k.surface), 1.15, "\(theme) filled (yours) reads apart from outlined")
        }
    }

    func test_LAB2056_disabledLabelsAndHealthBars() {
        for theme in ThemeName.panelChoices {
            let k = theme.tokens
            XCTAssertGreaterThanOrEqual(RGB.contrast(LoopLook.disabledLabel(theme), k.surface), 3, "\(theme) disabled label/button on card")
            XCTAssertGreaterThanOrEqual(RGB.contrast(LoopLook.unknownBar(theme), k.surface), 3, "\(theme) unknown health bar/card")
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.text2, k.surface), 4.5, "\(theme) field labels (ORIGIN, KIND …)/card")
        }
    }
}
