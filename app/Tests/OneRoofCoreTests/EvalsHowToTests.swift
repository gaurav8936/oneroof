import XCTest
@testable import OneRoofCore

/// LAB-2113: Evals › How to — eight scenes covering the three jobs, each opening the tab it talks about; progress is
/// remembered; narration plays only when the deck carries the card with audio.
final class EvalsHowToTests: XCTestCase {
    func test_LAB2113_howToIsTheFirstTab() {
        XCTAssertEqual(EvalsTabV2.allCases.first, .howTo)
        XCTAssertEqual(EvalsTabV2.howTo.title, "How to")
        XCTAssertEqual(EvalsTabV2.selfTest("how-to")?.tab, .howTo)
    }

    func test_LAB2113_eightScenesNamingTheThreeJobs() {
        XCTAssertEqual(EvalsHowTo.scenes.count, 8)
        XCTAssertEqual(Set(EvalsHowTo.scenes.map(\.id)).count, 8)
        let first = EvalsHowTo.scenes[0].body
        for job in ["public benchmarks", "your own work", "build and keep your own eval sets"] { XCTAssertTrue(first.contains(job), job) }
        XCTAssertTrue(EvalsHowTo.scenes[1].body.contains("Run this"))   // a first eval
        // Every scene opens a tab, and together they reach every tab but How to itself.
        XCTAssertTrue(EvalsHowTo.scenes.allSatisfy { $0.tab != nil })
        XCTAssertEqual(Set(EvalsHowTo.scenes.compactMap(\.tab)), Set(EvalsTabV2.allCases.filter { $0 != .howTo }))
    }

    func test_LAB2113_progressIsRemembered() {
        var d = EvalsHowTo.done("")
        XCTAssertEqual(EvalsHowTo.next(d).id, "for")
        d.insert("first"); d.insert("for")
        let s = EvalsHowTo.store(d)
        XCTAssertEqual(s, "for,first")                      // scene order, not insertion order
        XCTAssertEqual(EvalsHowTo.done(s), d)
        XCTAssertEqual(EvalsHowTo.next(d).id, "read")
        XCTAssertEqual(EvalsHowTo.progressLine(d), "2 of 8 read")
    }

    func test_LAB2113_narrationOnlyWithTheCardAndAudio() {
        XCTAssertEqual(EvalsHowTo.narration(cardPresent: false, tracks: 0), .coming)
        XCTAssertEqual(EvalsHowTo.narration(cardPresent: true, tracks: 0), .coming)
        XCTAssertEqual(EvalsHowTo.narration(cardPresent: true, tracks: 8), .playable(tracks: 8))
        XCTAssertEqual(EvalsHowTo.track(for: "next", tracks: 8), 7)
        XCTAssertEqual(EvalsHowTo.track(for: "next", tracks: 3), 2)   // clamped to the card's tracks
    }
}
