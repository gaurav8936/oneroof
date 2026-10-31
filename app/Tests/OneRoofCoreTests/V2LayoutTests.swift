import XCTest
@testable import OneRoofCore

/// 1.8.1 real-profile audit (LAB-1234): launch step for upgraded windows, the Sessions step kept across places, the
/// selected row past the exited cap, dragged widths, and the test-only profile seed filter.
final class V2LayoutTests: XCTestCase {
    func testSavedStepWins() {
        XCTAssertEqual(V2Layout.initialStep(saved: 2, existedBefore: true), .wide)
        XCTAssertEqual(V2Layout.initialStep(saved: 0, existedBefore: false), .full)
    }

    func testWindowFrom0529OpensAtFullAndNewWindowAtSessions() {
        XCTAssertEqual(V2Layout.initialStep(saved: nil, existedBefore: true), .full)
        XCTAssertEqual(V2Layout.initialStep(saved: nil, existedBefore: false), .sessions)
        XCTAssertEqual(V2Layout.initialStep(saved: 9, existedBefore: false), .sessions)   // junk value: the default
    }

    func testSessionsReturnsToItsLastStepOtherPlacesToTheirDefault() {
        XCTAssertEqual(V2Layout.openingStep(.sessions, sessionsStep: nil), .sessions)
        XCTAssertEqual(V2Layout.openingStep(.sessions, sessionsStep: .full), .full)
        XCTAssertEqual(V2Layout.openingStep(.home, sessionsStep: .wide), .full)
        XCTAssertEqual(V2Layout.openingStep(.machine, sessionsStep: nil), .full)
    }

    func testCappedRowsKeepTheSelectedRow() {
        let rows = (1...20).map { "s\($0)" }
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: []), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: ["s15"]), ["s1", "s2", "s3", "s4", "s15"])
        XCTAssertEqual(V2Layout.cappedRows(rows, cap: 4, id: { $0 }, keep: ["s2"]), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(V2Layout.cappedRows(["a", "b"], cap: 4, id: { $0 }, keep: ["x"]), ["a", "b"])
    }

    func testColumnWidthUsesTheDraggedWidthWithinLimits() {
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: nil), V2Layout.sessionsColumnMin())   // LAB-1783: 280 is under the icon row
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: nil), 250)
        XCTAssertEqual(V2Layout.columnWidth(step: .wide, saved: nil), 250)
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: 320), 320)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 900), 440)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 120), V2Layout.sessionsColumnMin())   // LAB-1783
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: 320), V2Layout.focusLane)
    }

    /// LAB-1783: at Sessions the column reaches past the toolbar's icon row (it ends at 91 + 198 pt), unless the
    /// window is too narrow to keep the centre's minimum; the window is never grown for it.
    func test_LAB1783_sessionsColumnHoldsThePlacesRow() {
        XCTAssertGreaterThanOrEqual(V2Layout.sessionsColumnMin(), V2Layout.Bar.lights + V2Layout.Bar.placesRow + 8)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 200, windowWidth: 1500), V2Layout.sessionsColumnMin())
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: 200, windowWidth: 1500), 200, "only step 1 has the icon row")
        let narrow = V2Layout.columnWidth(step: .sessions, saved: 200, windowWidth: V2Layout.minWindowWidth)
        XCTAssertLessThanOrEqual(narrow + V2Layout.planEdge + V2Layout.centreMin + 4, max(V2Layout.minWindowWidth, V2Layout.columnMin + V2Layout.planEdge + V2Layout.centreMin + 4))
        XCTAssertGreaterThanOrEqual(narrow, V2Layout.columnMin)
    }

    /// LAB-1829: the rail drags closed anywhere it shows, except over a folded Sessions column (LAB-1612's grab).
    func test_LAB1829_railFoldsAndItsEdgeLocksOnlyOverAFoldedColumn() {
        XCTAssertTrue(V2Layout.showsRail(step: .full, inSessions: true, folded: false))
        XCTAssertFalse(V2Layout.showsRail(step: .full, inSessions: true, folded: true), "folded by you")
        XCTAssertFalse(V2Layout.showsRail(step: .sessions, inSessions: true, folded: false), "step 1 hides it")
        XCTAssertTrue(V2Layout.showsRail(step: .sessions, inSessions: false, folded: false), "other places keep it")
        XCTAssertFalse(V2Layout.showsRail(step: .full, inSessions: false, folded: true))
        XCTAssertTrue(V2Layout.railEdgeLocked(inSessions: true, columnFolded: true, railShown: true))
        XCTAssertFalse(V2Layout.railEdgeLocked(inSessions: true, columnFolded: false, railShown: true))
        XCTAssertFalse(V2Layout.railEdgeLocked(inSessions: false, columnFolded: true, railShown: true), "Learn, Home…")
        // A folded rail: the places row is over the column at any step, so the column holds it.
        XCTAssertEqual(V2Layout.columnWidth(step: .full, saved: 220, windowWidth: 1500, placesRow: true), V2Layout.sessionsColumnMin())
    }

    /// LAB-1828: Focus and Single · Grid · Wall only where they arrange something: the Sessions place.
    func test_LAB1828_sessionControlsOnlyInSessions() {
        XCTAssertTrue(V2Layout.showsStepButton(inSessions: true, page: nil))
        XCTAssertFalse(V2Layout.showsStepButton(inSessions: false, page: nil), "Learn, Home, Needs you…")
        XCTAssertFalse(V2Layout.showsStepButton(inSessions: true, page: "Settings"))
        XCTAssertTrue(V2Layout.showsLayoutControl(inSessions: true, page: nil))
        XCTAssertTrue(V2Layout.showsLayoutControl(inSessions: true, page: "All windows"), "the Wall: Single goes back")
        XCTAssertFalse(V2Layout.showsLayoutControl(inSessions: false, page: nil))
        XCTAssertFalse(V2Layout.showsLayoutControl(inSessions: true, page: "Settings"))
    }

    /// LAB-1783: the title text lines up with the centre's content (1.9.28 measures), never over the window buttons.
    func test_LAB1783_titleLinesUpWithTheCentre() {
        XCTAssertEqual(V2Layout.titleShift(itemX: 281, centreX: 269), 0, "Full: already there")
        XCTAssertEqual(V2Layout.titleShift(itemX: 315, centreX: 303), 0, "Sessions")
        XCTAssertEqual(V2Layout.titleShift(itemX: 100, centreX: 68), -20, "Focus lane / rail: drawn back to the centre")
        XCTAssertEqual(V2Layout.titleShift(itemX: 100, centreX: 269), 181, "no separator item: drawn right, past the column")
        // Nothing left of the centre (it starts at the window's edge): the text stops 18 pt after the zoom button.
        XCTAssertEqual(V2Layout.titleShift(itemX: 100, centreX: 0, lightsEnd: 60), -30)
        XCTAssertEqual(V2Layout.titleShift(itemX: 100, centreX: 68, lightsEnd: 60), -20, "the lane's edge is further right")
    }

    /// LAB-1366: at Focus the avatar lane can be dragged wide to show the full list; its own width, kept apart from
    /// the other steps' column width; narrow again snaps back to the 52 pt avatars.
    func test_LAB1366_focusLaneWidensAndSnapsBack() {
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: 320, focusWide: nil), V2Layout.focusLane)
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: 320, focusWide: 260), 260)
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: nil, focusWide: 900), 440)
        XCTAssertEqual(V2Layout.columnWidth(step: .sessions, saved: 360, focusWide: 260), 360, "other steps keep theirs")
        XCTAssertNil(V2Layout.focusLaneSnap(dragged: 52))
        XCTAssertNil(V2Layout.focusLaneSnap(dragged: 109))
        XCTAssertEqual(V2Layout.focusLaneSnap(dragged: 700), 440)
    }

    /// LAB-1383: Focus means the thin lane. A click on Focus (or 3 · Focus, ⌥⌘F) with the lane widened snaps it back
    /// and stays at Focus; only with the thin lane does the click move on to the next step.
    func test_LAB1383_focusClickSnapsTheLaneBack() {
        XCTAssertEqual(V2Layout.stepRequest(current: .focus, requested: .full, laneWide: true), .snapLane)
        XCTAssertEqual(V2Layout.stepRequest(current: .focus, requested: .focus, laneWide: true), .snapLane)
        XCTAssertEqual(V2Layout.stepRequest(current: .focus, requested: .full, laneWide: false), .step(.full))
        XCTAssertEqual(V2Layout.stepRequest(current: .full, requested: .focus, laneWide: true), .enterFocusThin)
        XCTAssertEqual(V2Layout.stepRequest(current: .full, requested: .wide, laneWide: true), .step(.wide))
    }

    /// LAB-1382: the lane shows the list as soon as it is wider than the avatars (text appears progressively, cut
    /// off, never wrapped), and a release keeps the width you dragged to instead of jumping to 200 pt.
    func test_LAB1382_focusLaneListFollowsTheLiveWidth() {
        XCTAssertFalse(V2Layout.focusLaneShowsList(width: 52))
        XCTAssertFalse(V2Layout.focusLaneShowsList(width: 109))
        XCTAssertTrue(V2Layout.focusLaneShowsList(width: 110))
        XCTAssertTrue(V2Layout.focusLaneShowsList(width: 300))
        XCTAssertEqual(V2Layout.focusLaneSnap(dragged: 140), 140, "kept where you let go")
        XCTAssertEqual(V2Layout.focusLaneSnap(dragged: 300), 300)
        XCTAssertEqual(V2Layout.columnWidth(step: .focus, saved: nil, focusWide: 140), 140)
    }

    /// LAB-1363: "Current ↓" shows whenever the terminal is scrolled up from its live bottom (not only while a step
    /// is open), never over the Table view or the raw stream, and not before libghostty has reported a position.
    func test_LAB1363_currentPillShowsWhenScrolledUp() {
        XCTAssertTrue(V2Layout.showsCurrentPill(atBottom: false, raw: false, table: false))
        XCTAssertFalse(V2Layout.showsCurrentPill(atBottom: true, raw: false, table: false))
        XCTAssertFalse(V2Layout.showsCurrentPill(atBottom: nil, raw: false, table: false))
        XCTAssertFalse(V2Layout.showsCurrentPill(atBottom: false, raw: true, table: false))
        XCTAssertFalse(V2Layout.showsCurrentPill(atBottom: false, raw: false, table: true))
    }

    /// LAB-1363: ⌘↓ jumps to the live bottom (⌘↑ to the top), as in Terminal and Warp, while a terminal has focus.
    func test_LAB1363_commandDownScrollsToBottom() {
        XCTAssertTrue(V2Layout.terminalKeybinds.contains("keybind = super+arrow_down=scroll_to_bottom"))
        XCTAssertTrue(V2Layout.terminalKeybinds.contains("keybind = super+arrow_up=scroll_to_top"))
    }

    /// LAB-1367 / LAB-1368: the edge panels open only after the pointer rests at the edge (owner: 1–2 s).
    func test_LAB1367_edgeRevealWaits() {
        XCTAssertGreaterThanOrEqual(V2Layout.edgeRevealDwell, 1.0)
        XCTAssertLessThanOrEqual(V2Layout.edgeRevealDwell, 2.0)
    }

    func testPlanWidth() {
        XCTAssertEqual(V2Layout.planWidth(saved: nil), 270)
        XCTAssertEqual(V2Layout.planWidth(saved: 300), 300)
        XCTAssertEqual(V2Layout.planWidth(saved: 100), 240)
        XCTAssertEqual(V2Layout.planWidth(saved: 2000), 520)
    }

    func testSeedFilterDropsAppKitAndRoofdKeys() {
        let kept = SeedFilter.keep(["settings": Data(), "focusStep.A": 3, "NSWindow Frame OneRoofMain": "x",
                                    "NSSplitView Subview Frames OneRoofSplit": ["a"], "roofd.registeredBuild": 1.0, "OneRoofPanes.A": Data()])
        XCTAssertEqual(Set(kept.keys), ["settings", "focusStep.A", "OneRoofPanes.A"])
    }
}

/// 1.8.2 (LAB-831, LAB-1237, LAB-596): the v2 window goes down to about a third of the screen without growing itself,
/// and the toolbar's right group never clips.
final class V2NarrowWindowTests: XCTestCase {
    /// LAB-831: the minimum is about a third of a laptop screen; the classic window keeps its own.
    func testV2MinimumIsAboutAThirdOfTheScreen() {
        XCTAssertLessThanOrEqual(V2Layout.minWindowWidth, 640)
        XCTAssertEqual(PanelMinimums.windowWidth, 1000, "the classic window is unchanged")
    }

    /// LAB-596: at every step, the narrowest layout (Plan folded to its edge tab, column at its minimum) fits the
    /// smallest window, so AppKit never grows the window to make room.
    func testEveryStepFitsTheSmallestWindow() {
        for step in FocusStep.allCases {
            XCTAssertLessThanOrEqual(V2Layout.narrowestFit(step: step), V2Layout.minWindowWidth, "\(step)")
        }
    }

    /// LAB-831: the Plan inspector keeps its column at Full only while it fits; never in a third-of-a-screen window.
    func testPlanFoldsToTheEdgeTabWhenTheWindowIsNarrow() {
        XCTAssertTrue(V2Layout.planFits(windowWidth: 1000, rail: true, column: 250))
        XCTAssertTrue(V2Layout.planFits(windowWidth: 1440, rail: true, column: 440))
        XCTAssertFalse(V2Layout.planFits(windowWidth: 800, rail: true, column: 250))
        XCTAssertFalse(V2Layout.planFits(windowWidth: 600, rail: true, column: 200))
        XCTAssertFalse(V2Layout.planFits(windowWidth: 870, rail: true, column: 320), "a wider dragged column folds it sooner")
        // Judged on the column's chosen width with its minimum, never below it.
        XCTAssertEqual(V2Layout.planFits(windowWidth: 810, rail: true, column: 100), V2Layout.planFits(windowWidth: 810, rail: true, column: 200))
    }

    /// LAB-1237: the right group (step button, + New, and Single · Grid · Wall when shown) plus the title always fit
    /// the room, from a third-of-a-screen window to a wide one.
    func testToolbarRightGroupNeverClips() {
        typealias B = V2Layout.Bar
        for room in stride(from: 240.0, through: 1700, by: 10) {
            for extras in [0.0, 200] {
                let f = V2Layout.toolbarFit(room: room, extras: extras)
                let right = B.trailing + B.new + B.gap + (f.shortcuts ? B.stepFull : B.stepShort) + B.gap
                    + (f.layoutControl ? B.layout + B.gap : 0) + (extras > 0 ? extras + B.gap : 0)
                let title = f.titleWidth > 0 ? f.titleWidth + B.titleLead : 0
                if f.titleWidth > 0 || f.layoutControl || f.shortcuts {
                    XCTAssertLessThanOrEqual(right + title, room, "room \(room) extras \(extras): \(f)")
                }
                XCTAssertTrue(f.titleWidth == 0 || f.titleWidth >= 48, "a title is readable or gone")
                // More room never takes a piece away: the right group only grows back as the window widens.
                let more = V2Layout.toolbarFit(room: room + 10, extras: extras)
                XCTAssertTrue((more.shortcuts || !f.shortcuts) && (more.layoutControl || !f.layoutControl), "room \(room)")
                XCTAssertFalse(f.shortcuts && !f.layoutControl, "the shortcut labels go before Single · Grid · Wall")
            }
        }
    }

    func testToolbarDegradesInOrder() {
        let wide = V2Layout.toolbarFit(room: 1400)
        XCTAssertEqual(wide, .init(titleWidth: 620, subtitle: true, shortcuts: true, layoutControl: true))
        let mid = V2Layout.toolbarFit(room: 676)   // 1000 pt window at step 1
        XCTAssertTrue(mid.shortcuts && mid.layoutControl)
        XCTAssertFalse(mid.subtitle, "the subtitle goes before the shortcuts")
        let narrow = V2Layout.toolbarFit(room: 276)   // 600 pt window at step 1: step button and + New only
        XCTAssertEqual(narrow, .init(titleWidth: 0, subtitle: false, shortcuts: false, layoutControl: false))
    }

    func testToolbarStartsAfterTheIconRowWhenItReachesFurther() {
        XCTAssertEqual(V2Layout.toolbarStart(divider: 316, placesRow: false), 316 + V2Layout.Bar.sectionLead)
        XCTAssertEqual(V2Layout.toolbarStart(divider: 200, placesRow: true), V2Layout.Bar.lights + V2Layout.Bar.placesRow + V2Layout.Bar.sectionLead)
        XCTAssertEqual(V2Layout.toolbarStart(divider: 52, placesRow: false), V2Layout.Bar.lights + V2Layout.Bar.sectionLead, "Focus: after the traffic lights")
    }
}
