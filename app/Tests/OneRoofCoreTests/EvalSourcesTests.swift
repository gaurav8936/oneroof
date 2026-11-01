import XCTest
@testable import OneRoofCore

/// LAB-2117: every benchmark discloses its data source and licence; gated Hugging Face sets stay locked until the
/// user's own sign-in and accepted terms; the engine never inherits a token.
final class EvalSourcesTests: XCTestCase {
    func test_LAB2117_theFourGatedSetsAreLockedOnAFreshProfile() {
        XCTAssertEqual(EvalSources.gatedFolders, ["gaia", "hle", "livecodebench_pro", "xstest"])
        for f in EvalSources.gatedFolders {
            XCTAssertEqual(EvalGate.status(EvalSources.table[f], signedIn: false, accepted: []), .needsSignIn)
            XCTAssertTrue(EvalGate.status(EvalSources.table[f], signedIn: false, accepted: []).locked)
        }
    }

    func test_LAB2117_signInThenTermsUnlocksOnlyThatSet() {
        let hle = EvalSources.table["hle"]
        XCTAssertEqual(EvalGate.status(hle, signedIn: true, accepted: []), .needsTerms)
        XCTAssertEqual(EvalGate.status(hle, signedIn: true, accepted: ["hle"]), .unlocked)
        XCTAssertEqual(EvalGate.status(EvalSources.table["gaia"], signedIn: true, accepted: ["hle"]), .needsTerms)
        XCTAssertEqual(EvalGate.status(EvalSources.table["gsm8k"], signedIn: false, accepted: []), .open)
    }

    func test_LAB2117_everyBenchmarkHasASourceAndLicenceLine() {
        for (f, s) in EvalSources.table {
            XCTAssertFalse(s.licence.isEmpty, f)
            XCTAssertTrue(s.url.hasPrefix("https://"), f)
            let line = EvalSources.line(s)
            XCTAssertTrue(line.contains("Licence"), f)
            XCTAssertTrue(line.hasSuffix(EvalSources.shipLine), f)
        }
        XCTAssertEqual(EvalSources.line(EvalSources.table["hle"]!),
                       "Data: cais/hle (Hugging Face) · Licence MIT · Downloaded to this Mac on first use; One Roof does not ship it.")
        // Unknown benchmark: the engine's dataset id and gated flag; your own sets disclose nothing third-party.
        XCTAssertEqual(EvalSources.source(folder: "newbench", dataset: "org/set", gated: true)?.gated, true)
        XCTAssertNil(EvalSources.source(folder: "own-fixes"))
    }

    func test_LAB2117_startRefusedForALockedSet() {
        let folder: (String) -> String? = { ["hle": "hle", "gsm8k": "gsm8k"][$0] }
        XCTAssertNotNil(EvalGate.startReason(tasks: ["gsm8k", "hle"], folderOf: folder, signedIn: false, accepted: []))
        XCTAssertNotNil(EvalGate.startReason(tasks: ["hle"], folderOf: folder, signedIn: true, accepted: []))
        XCTAssertNil(EvalGate.startReason(tasks: ["hle"], folderOf: folder, signedIn: true, accepted: ["hle"]))
        XCTAssertNil(EvalGate.startReason(tasks: ["gsm8k"], folderOf: folder, signedIn: false, accepted: []))
    }

    func test_LAB2117_engineNeverInheritsAToken() {
        let env = EvalEngine.hfEnvironment(["HF_TOKEN": "hf_inherited", "HUGGING_FACE_HUB_TOKEN": "hf_x", "PATH": "/bin"], extra: [:])
        XCTAssertNil(env["HF_TOKEN"])
        XCTAssertNil(env["HUGGING_FACE_HUB_TOKEN"])
        XCTAssertEqual(env["ONEROOF_HF_ACCEPTED"], "")
        XCTAssertTrue(env["HF_TOKEN_PATH"]?.hasSuffix("/no-cached-hf-token") ?? false)
        let signed = EvalEngine.hfEnvironment([:], extra: ["HF_TOKEN": "hf_own", "ONEROOF_HF_ACCEPTED": EvalGate.acceptedEnv(["xstest", "hle"])])
        XCTAssertEqual(signed["HF_TOKEN"], "hf_own")
        XCTAssertEqual(signed["ONEROOF_HF_ACCEPTED"], "hle,xstest")
    }

    func test_LAB2117_tokenShape() {
        XCTAssertTrue(EvalGate.looksLikeToken("hf_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(EvalGate.looksLikeToken("xx_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(EvalGate.looksLikeToken("hf_short"))
        XCTAssertFalse(EvalGate.looksLikeToken("hf_abc def ghi jkl mno pqr"))
    }
}
