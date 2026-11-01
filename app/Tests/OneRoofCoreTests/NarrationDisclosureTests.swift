import XCTest
@testable import OneRoofCore

/// LAB-2116: the AI-voice disclosure every narrated player shows, word for word as the issue asks.
final class NarrationDisclosureTests: XCTestCase {
    func test_LAB2116_disclosureWording() {
        XCTAssertEqual(Narration.disclosure, "Narration: AI-generated voice (OpenAI text-to-speech).")
        XCTAssertTrue(Narration.detail.contains("not a human voice"))
        XCTAssertTrue(Narration.policyURL.hasPrefix("https://openai.com/policies/"))
    }
}
