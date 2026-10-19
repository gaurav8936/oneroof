import XCTest
@testable import OneRoofCore

/// S07 §1.2 / §1.7: Run / Debug commands and the interpreter label, detected from a temp repo tree.
final class RunConfigTests: XCTestCase {
    var root = ""
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = (fm.temporaryDirectory.appendingPathComponent("oneroof-run-\(UUID().uuidString)").path as NSString).standardizingPath
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    func write(_ rel: String, _ text: String = "", executable: Bool = false) throws {
        let path = root + "/" + rel
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: path, contents: Data(text.utf8), attributes: executable ? [.posixPermissions: 0o755] : nil)
    }

    func testPythonFallsBackToEnvPython3() {
        let file = root + "/tool.py"
        XCTAssertEqual(RunConfig.detect(file: file, repoRoot: root),
                       RunConfig(label: "python3", run: ["/usr/bin/env", "python3", file],
                                 debug: ["/usr/bin/env", "python3", "-m", "pdb", file], cwd: root))
    }

    func testPythonUsesUvWhenLocked() throws {
        try write("uv.lock")
        let file = root + "/src/app.py"
        let c = RunConfig.detect(file: file, repoRoot: root)
        XCTAssertEqual(c?.run, ["uv", "run", "python", file])
        XCTAssertEqual(c?.debug, ["uv", "run", "python", "-m", "pdb", file])
        XCTAssertEqual(RunConfig.detect(file: root + "/tests/test_app.py", repoRoot: root)?.run,
                       ["uv", "run", "python", "-m", "pytest", root + "/tests/test_app.py"])
    }

    func testPythonPrefersVenvWithVersionLabel() throws {
        try write("uv.lock")
        try write(".venv/bin/python", "#!/bin/sh\n", executable: true)
        try write(".venv/pyvenv.cfg", "home = /opt/homebrew/bin\ninclude-system-site-packages = false\nversion = 3.12.4\n")
        let py = root + "/.venv/bin/python"
        XCTAssertEqual(RunConfig.pythonVersion(at: py), "3.12")

        let file = root + "/main.py"
        XCTAssertEqual(RunConfig.detect(file: file, repoRoot: root),
                       RunConfig(label: "Python 3.12 · .venv", run: [py, file], debug: [py, "-m", "pdb", file], cwd: root))
        // Relative paths resolve against the repo root; *_test.py runs pytest.
        let test = RunConfig.detect(file: "pkg/thing_test.py", repoRoot: root)
        XCTAssertEqual(test?.run, [py, "-m", "pytest", root + "/pkg/thing_test.py"])
        XCTAssertEqual(test?.debug, [py, "-m", "pytest", "--pdb", root + "/pkg/thing_test.py"])

        // uv writes version_info instead of version.
        try write(".venv/pyvenv.cfg", "implementation = CPython\nuv = 0.4.0\nversion_info = 3.11.9.final.0\n")
        XCTAssertEqual(RunConfig.pythonVersion(at: py), "3.11")
        try write(".venv/pyvenv.cfg", "home = /usr/bin\n")
        XCTAssertNil(RunConfig.pythonVersion(at: py))
        XCTAssertEqual(RunConfig.detect(file: file, repoRoot: root)?.label, "Python · .venv")
        XCTAssertNil(RunConfig.pythonVersion(at: root + "/missing/bin/python"))
    }

    func testSwiftPackage() throws {
        try write("app/Package.swift", "// swift-tools-version:6.0\n")
        let pkg = root + "/app"
        XCTAssertEqual(RunConfig.detect(file: pkg + "/Tests/CoreTests/ATests.swift", repoRoot: root),
                       RunConfig(label: "swift test", run: ["swift", "test"], debug: nil, cwd: pkg))
        XCTAssertEqual(RunConfig.detect(file: pkg + "/Sources/Core/A.swift", repoRoot: root),
                       RunConfig(label: "swift build", run: ["swift", "build"], debug: nil, cwd: pkg))
        // A loose script outside any package runs with the swift interpreter.
        XCTAssertEqual(RunConfig.detect(file: root + "/scripts/tool.swift", repoRoot: root)?.run,
                       ["/usr/bin/env", "swift", root + "/scripts/tool.swift"])
    }

    func testNode() throws {
        let js = root + "/web/index.js"
        XCTAssertEqual(RunConfig.detect(file: js, repoRoot: root)?.run, ["/usr/bin/env", "node", js])
        XCTAssertNil(RunConfig.detect(file: root + "/web/a.ts", repoRoot: root), "TypeScript needs a test script")

        try write("web/package.json", #"{"name": "web", "scripts": {"test": "echo \"Error: no test specified\" && exit 1"}}"#)
        XCTAssertEqual(RunConfig.detect(file: js, repoRoot: root)?.label, "node", "npm init placeholder is not a test script")

        try write("web/package.json", #"{"name": "web", "scripts": {"build": "tsc", "test": "vitest run"}}"#)
        let expected = RunConfig(label: "npm run test", run: ["npm", "run", "test"], debug: nil, cwd: root + "/web")
        XCTAssertEqual(RunConfig.detect(file: js, repoRoot: root), expected)
        XCTAssertEqual(RunConfig.detect(file: root + "/web/src/deep/a.ts", repoRoot: root), expected)
    }

    func testShellAndOthers() {
        XCTAssertEqual(RunConfig.detect(file: root + "/scripts/go.sh", repoRoot: root),
                       RunConfig(label: "zsh", run: ["/bin/zsh", root + "/scripts/go.sh"], debug: nil, cwd: root))
        XCTAssertEqual(RunConfig.detect(file: root + "/x.zsh", repoRoot: root)?.run.first, "/bin/zsh")
        XCTAssertEqual(RunConfig.detect(file: root + "/x.bash", repoRoot: root)?.run.first, "/bin/bash")
        XCTAssertNil(RunConfig.detect(file: root + "/README.md", repoRoot: root))
        XCTAssertNil(RunConfig.detect(file: root + "/data.json", repoRoot: root))
    }
}
