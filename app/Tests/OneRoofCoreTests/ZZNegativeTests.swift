import XCTest

// CMN-ACTIONS-OFF negative check: DO NOT MERGE. Must turn the Mac workflow red.
final class DeliberateFailureTests: XCTestCase {
    func testDeliberateFailure() { XCTFail("deliberate failure: Woodpecker Mac workflow must be red") }
}
