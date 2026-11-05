import XCTest
@testable import OneRoofCore

/// LAB-2219 · the app never lets the bundled engine write `__pycache__` into the signed bundle: every launch of
/// roof_eval.py passes PYTHONDONTWRITEBYTECODE=1 (the engine also sets sys.dont_write_bytecode for its children).
final class EvalEngineEnvironmentTests: XCTestCase {
    func test_LAB2219_engine_runs_without_writing_bytecode() {
        let env = EvalEngine.environment(["PATH": "/usr/bin:/bin", "HF_TOKEN": "hf_inherited"], extra: [:])
        XCTAssertEqual(env["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(env["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")   // uv, docker
        XCTAssertNil(env["HF_TOKEN"])                                                     // LAB-2117 kept
        // An inherited 0 is overridden too.
        XCTAssertEqual(EvalEngine.environment(["PYTHONDONTWRITEBYTECODE": "0"], extra: [:])["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(EvalEngine.environment([:], extra: ["HF_TOKEN": "hf_own"])["HF_TOKEN"], "hf_own")
    }
}
