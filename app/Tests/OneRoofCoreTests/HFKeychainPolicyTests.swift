import XCTest
@testable import OneRoofCore

/// LAB-2246 · LAB-2251 · who may touch the login Keychain for the Hugging Face token.
final class HFKeychainPolicyTests: XCTestCase {
    let app = "/Applications/One Roof.app"

    func test_noKeychainEnv_noCallAtAll() {
        for v in ["1", "true", "YES"] {
            XCTAssertEqual(HFKeychainPolicy.decision(env: ["ONEROOF_NO_KEYCHAIN": v], bundlePath: app, trusted: true), .disabledForTests)
            XCTAssertFalse(HFKeychainPolicy.mayRead(env: ["ONEROOF_NO_KEYCHAIN": v], bundlePath: app, trusted: true, prompt: true))
        }
        XCTAssertFalse(HFKeychainPolicy.disabled(env: ["ONEROOF_NO_KEYCHAIN": "0"]))
        XCTAssertFalse(HFKeychainPolicy.disabled(env: [:]))
    }

    func test_onlyTheReleasedAppInApplicationsReads() {
        XCTAssertTrue(HFKeychainPolicy.mayRead(env: [:], bundlePath: app, trusted: true, prompt: false))
        XCTAssertTrue(HFKeychainPolicy.mayRead(env: [:], bundlePath: app, trusted: true, prompt: true), "the Test button may prompt")
        // Ad hoc / unsigned anywhere, even in /Applications.
        XCTAssertFalse(HFKeychainPolicy.mayRead(env: [:], bundlePath: app, trusted: false, prompt: false))
        XCTAssertFalse(HFKeychainPolicy.mayRead(env: [:], bundlePath: app, trusted: false, prompt: true), "a prompt never widens it")
        // Developer ID signed, but a copy elsewhere: a candidate in a release folder, a test copy, a scratch bundle.
        for p in ["/Users/you/Projects/labs/oneroof/app/build/One Roof.app", "/tmp/claude-501/ort.x/One Roof.app",
                  "/Applications/Old/One Roof.app", "/Users/you/Applications/One Roof.app", "/Applications/../tmp/One Roof.app"] {
            XCTAssertEqual(HFKeychainPolicy.decision(env: [:], bundlePath: p, trusted: true), .untrustedCopy, p)
        }
    }

    func test_lockedLineSaysWhy() {
        XCTAssertNil(HFKeychainPolicy.lockedLine(.allowed))
        XCTAssertTrue(HFKeychainPolicy.lockedLine(.disabledForTests)!.contains("ONEROOF_NO_KEYCHAIN=1"))
        XCTAssertTrue(HFKeychainPolicy.lockedLine(.untrustedCopy)!.contains("/Applications"))
    }
}
