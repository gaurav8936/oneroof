import XCTest
@testable import OneRoofCore

/// LAB-2332 / LAB-2331: the 13-place rail, its groups, keys, placeholders and spacing.
final class RailPlacesTests: XCTestCase {
    func testThirteenPlacesInOrderAndGroups() {
        XCTAssertEqual(Place.allCases, [.home, .needsYou, .sessions, .work, .agents, .factory, .loops, .trace, .machine, .evals, .train, .ship, .learn])
        XCTAssertEqual(Place.allCases.map(\.title), ["Home", "Inbox", "Sessions", "Projects", "Agents", "Factory", "Loops", "Trace", "Resources", "Evals", "Train", "Ship", "Learn"])
        XCTAssertEqual(PlaceGroup.allCases.map { $0.places.count }, [4, 2, 3, 2, 1, 1])
        // Groups are contiguous in the rail order.
        let groups = Place.allCases.map(\.group)
        XCTAssertEqual(groups.enumerated().filter { $0.offset == 0 || groups[$0.offset - 1] != $0.element }.map(\.element), PlaceGroup.allCases)
    }

    func testEveryPlaceHasAUniqueKeyAndASymbol() {
        let keys = Place.allCases.map(\.controlKey)
        XCTAssertEqual(Set(keys).count, keys.count, "no two places share a key")
        XCTAssertFalse(keys.contains("F"), "⌃⌘F is macOS's full screen")
        XCTAssertFalse(keys.contains("Q"), "⌃⌘Q is macOS's lock screen")
        XCTAssertFalse(keys.contains("D"), "⌃⌘D is macOS's look up")
        for p in Place.allCases { XCTAssertFalse(p.symbol.isEmpty, "\(p)") }
        let old: [Place: Character] = [.home: "1", .needsYou: "2", .sessions: "3", .work: "4", .machine: "5", .loops: "6", .learn: "7", .evals: "8"]
        for (p, k) in old { XCTAssertEqual(p.controlKey, k, "\(p) keeps ⌃⌘\(k)") }
    }

    func testStoredHistoryReadsAsTrace() throws {
        XCTAssertEqual(Place(rawValue: "history"), .trace)
        XCTAssertEqual(Place(rawValue: "machine"), .machine)
        XCTAssertNil(Place(rawValue: "nowhere"))
        let decoded = try JSONDecoder().decode([Place].self, from: Data(#"["history","evals"]"#.utf8))
        XCTAssertEqual(decoded, [.trace, .evals])
        XCTAssertEqual(try JSONDecoder().decode([Place].self, from: JSONEncoder().encode(Place.allCases)), Place.allCases)
    }

    func testPlannedPlacesHaveTheirCopy() {
        XCTAssertEqual(Place.allCases.filter(\.isPlanned), [.agents, .factory, .train, .ship])
        for c in PlannedPlaceCopy.all {
            XCTAssertFalse(c.oneLine.isEmpty, "\(c.place)")
            XCTAssertTrue((3...5).contains(c.coming.count), "\(c.place): 3 to 5 coming lines")
            XCTAssertFalse(c.today.isEmpty, "\(c.place)")
            XCTAssertFalse(c.tickets.isEmpty, "\(c.place)")
            for t in c.tickets { XCTAssertNotNil(PlannedPlaceCopy.ticketURL(t, workspace: "example")); XCTAssertTrue(t.hasPrefix("LAB-")) }
            for (_, link) in c.today { if case .place(let p) = link { XCTAssertFalse(p.isPlanned, "\(c.place) points at a real place") } }
        }
        XCTAssertEqual(PlannedPlaceCopy.of(.factory)?.tickets, ["LAB-1246", "LAB-2329", "LAB-1245", "LAB-198", "LAB-2330"])
        XCTAssertNil(PlannedPlaceCopy.of(.trace), "Trace is real: it opens on History")
        XCTAssertNil(PlannedPlaceCopy.ticketURL("LAB-1", workspace: nil), "no Linear connected: the id shows as text")
        XCTAssertEqual(PlannedPlaceCopy.workspace(fromLinearURLs: ["", "https://example.com/a/b", "https://linear.app/acme/project/x-1"]), "acme")
        XCTAssertNil(PlannedPlaceCopy.workspace(fromLinearURLs: ["https://linear.app/"]))
    }

    func testIconRowKeepsTheToolbarWidth() {
        XCTAssertEqual(V2Layout.Bar.placesRow, 198, "six icons + more = the 1.9.28 row, so the toolbar does not move")
        XCTAssertTrue(Place.iconRow.allSatisfy { !$0.isPlanned })
        XCTAssertEqual(V2Layout.toolbarStart(divider: 200, placesRow: true), 91 + 198 + V2Layout.Bar.sectionLead)
    }

    // MARK: LAB-2331 spacing

    func testTallWindowSpreadsThePlaces() {
        let f = V2Layout.Rail.fit(available: V2Layout.Rail.available(windowHeight: 1100))
        XCTAssertEqual(f.button, 48); XCTAssertEqual(f.gap, 12); XCTAssertEqual(f.groupGap, 14); XCTAssertFalse(f.scrolls)
        XCTAssertGreaterThan(f.gap, 4, "looser than 2.0.7's 4 pt")
    }

    func testEveryWindowHeightFitsWithoutClipping() {
        for h in [700.0, 800, 900, 1000, 1100, 1400] {
            let avail = V2Layout.Rail.available(windowHeight: h)
            let f = V2Layout.Rail.fit(available: avail)
            XCTAssertFalse(f.scrolls, "\(h) pt scrolls")
            XCTAssertLessThanOrEqual(f.height(places: 13, groups: 6), avail, "\(h) pt overflows")
            XCTAssertTrue((V2Layout.Rail.gapMin...V2Layout.Rail.gapMax).contains(f.gap))
            XCTAssertGreaterThanOrEqual(f.button, V2Layout.Rail.buttonMin)
        }
    }

    func testShortWindowTakesRoomBackInOrder() {
        let r = V2Layout.Rail.self
        // 900 pt: full buttons, the places closer together.
        let at900 = r.fit(available: r.available(windowHeight: 900))
        XCTAssertEqual(at900.button, 48); XCTAssertEqual(at900.groupGap, 14)
        // 700 pt with the dock: places at 4, group gaps at 8, buttons shorter (the icon shrinks with them).
        let at700 = r.fit(available: r.available(windowHeight: 700))
        XCTAssertEqual(at700.gap, 4); XCTAssertEqual(at700.groupGap, 8); XCTAssertLessThan(at700.button, 40)
        XCTAssertEqual(r.available(windowHeight: 700), 524, "measured in the 2.0.8 capture: 524 pt between the rail's top and Settings")
        XCTAssertEqual(r.iconFrame(button: 48), 24); XCTAssertEqual(r.iconFrame(button: 35), 21); XCTAssertEqual(r.iconFrame(button: 20), 18)
        // Smaller than the window minimum: the list scrolls, Settings stays.
        XCTAssertTrue(r.fit(available: 300).scrolls)
        // The seat bars at step 2 take room from the places, never from Settings.
        XCTAssertLessThan(r.available(windowHeight: 900, seats: 80), r.available(windowHeight: 900))
    }
}
