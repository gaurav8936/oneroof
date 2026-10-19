import Foundation

/// What ▶ Run (⌘R) and Debug (⇧⌘R) do for the open file (S07 §1.2, §1.7), and the interpreter menu's label.
/// Detected from the repo, never configured: a .venv, uv.lock, Package.swift or package.json decides.
public struct RunConfig: Equatable, Sendable {
    /// The interpreter menu: "Python 3.12 · .venv", "swift test", "npm run test".
    public var label: String
    /// argv for the run dock ("Run: file" tab).
    public var run: [String]
    /// argv for Debug (pdb / lldb in the dock); nil when there is no debugger story for this file.
    public var debug: [String]?
    public var cwd: String

    public init(label: String, run: [String], debug: [String]?, cwd: String) {
        self.label = label; self.run = run; self.debug = debug; self.cwd = cwd
    }

    public static func detect(file: String, repoRoot: String, fileManager: FileManager = .default) -> RunConfig? {
        let path = file.hasPrefix("/") ? file : (repoRoot as NSString).appendingPathComponent(file)
        let name = (path as NSString).lastPathComponent
        switch SourceLanguage.detect(path: path) {
        case .python:
            let isTest = (name.hasPrefix("test_") || name.hasSuffix("_test.py")) && name.hasSuffix(".py")
            let venvPython = (repoRoot as NSString).appendingPathComponent(".venv/bin/python")
            if fileManager.isExecutableFile(atPath: venvPython) {
                let label = pythonVersion(at: venvPython).map { "Python \($0) · .venv" } ?? "Python · .venv"
                return python([venvPython], label: label, file: path, test: isTest, cwd: repoRoot)
            }
            if fileManager.fileExists(atPath: (repoRoot as NSString).appendingPathComponent("uv.lock")) {
                return python(["uv", "run", "python"], label: "uv run python", file: path, test: isTest, cwd: repoRoot)
            }
            return python(["/usr/bin/env", "python3"], label: "python3", file: path, test: isTest, cwd: repoRoot)

        case .swift:
            guard let pkg = enclosing("Package.swift", from: path, repoRoot: repoRoot, fileManager) else {
                return RunConfig(label: "swift", run: ["/usr/bin/env", "swift", path], debug: nil, cwd: repoRoot)
            }
            let std = (path as NSString).standardizingPath
            let rel = std.hasPrefix(pkg + "/") ? String(std.dropFirst(pkg.count + 1)) : ""
            return rel.hasPrefix("Tests/")
                ? RunConfig(label: "swift test", run: ["swift", "test"], debug: nil, cwd: pkg)
                : RunConfig(label: "swift build", run: ["swift", "build"], debug: nil, cwd: pkg)

        case .typescript, .javascript:
            let isJS = SourceLanguage.detect(path: path) == .javascript
            if let pkg = enclosing("package.json", from: path, repoRoot: repoRoot, fileManager), hasTestScript(pkg, fileManager) {
                return RunConfig(label: "npm run test", run: ["npm", "run", "test"], debug: nil, cwd: pkg)
            }
            guard isJS else { return nil }
            return RunConfig(label: "node", run: ["/usr/bin/env", "node", path],
                             debug: ["/usr/bin/env", "node", "inspect", path], cwd: repoRoot)

        case .shell:
            // A .bash script runs under bash; .sh and .zsh under zsh (the macOS login shell).
            let shell = name.hasSuffix(".bash") ? "/bin/bash" : "/bin/zsh"
            return RunConfig(label: (shell as NSString).lastPathComponent, run: [shell, path], debug: nil, cwd: repoRoot)

        default:
            return nil
        }
    }

    /// "3.12" from the pyvenv.cfg next to a venv's bin/ ("version = 3.12.4", or uv's "version_info = 3.12.4.final.0").
    public static func pythonVersion(at python: String) -> String? {
        let venv = ((python as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        guard let cfg = try? String(contentsOfFile: (venv as NSString).appendingPathComponent("pyvenv.cfg"), encoding: .utf8)
        else { return nil }
        var found: [String: String] = [:]
        for line in cfg.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { found[parts[0]] = parts[1] }
        }
        guard let full = found["version"] ?? found["version_info"] else { return nil }
        let nums = full.split(separator: ".")
        guard nums.count >= 2, Int(nums[0]) != nil, Int(nums[1]) != nil else { return nil }
        return "\(nums[0]).\(nums[1])"
    }

    // MARK: Helpers

    /// Python: run the file (pytest for test files); debug under pdb (pytest --pdb for test files).
    static func python(_ interp: [String], label: String, file: String, test: Bool, cwd: String) -> RunConfig {
        test
            ? RunConfig(label: label, run: interp + ["-m", "pytest", file], debug: interp + ["-m", "pytest", "--pdb", file], cwd: cwd)
            : RunConfig(label: label, run: interp + [file], debug: interp + ["-m", "pdb", file], cwd: cwd)
    }

    /// The nearest folder at or above the file (and not above the repo root) holding `marker`.
    static func enclosing(_ marker: String, from file: String, repoRoot: String, _ fm: FileManager) -> String? {
        let root = (repoRoot as NSString).standardizingPath
        var dir = ((file as NSString).deletingLastPathComponent as NSString).standardizingPath
        while true {
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(marker)) { return dir }
            if dir == root || dir == "/" || !dir.hasPrefix(root) { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    /// package.json has a real "test" script (npm init's "no test specified" placeholder does not count).
    static func hasTestScript(_ dir: String, _ fm: FileManager) -> Bool {
        guard let data = fm.contents(atPath: (dir as NSString).appendingPathComponent("package.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = obj["scripts"] as? [String: Any], let test = scripts["test"] as? String else { return false }
        return !test.contains("no test specified")
    }
}
