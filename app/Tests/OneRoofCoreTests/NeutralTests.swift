import XCTest
@testable import OneRoofCore

/// One Roof installs on any Mac: no author-specific folders, accounts or names in the code; everything comes from
/// settings, the environment or what is found on disk.
final class NeutralSourceTests: XCTestCase {
    /// Words that name the author's own workspace. Only the legacy-migration file may contain them.
    static let banned = ["gabblegrid", "hypothesys", "zibajoon", "agencium", "mindmesh", "labs-data",
                         "labs-agentic-engineering", "/labs/oneroof/", "gaurav", "ganarasi", "linear-commit-hook"]
    /// The app's own bundle id and repository, and the blog hub Learn › Writing reads (LAB-1251, owner decision; its
    /// address is written once, in BlogHub.defaultBase, and can be changed in the defaults).
    static let allowed = ["io.github.gaurav8936.oneroof", "github.com/gaurav8936/oneroof", "\"https://console.zibajoon.com\""]

    func testSourcesNameNoAuthorSpecificFoldersOrNames() throws {
        // Tests/OneRoofCoreTests/NeutralTests.swift → app/Sources
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources").path
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: sources) else { return XCTFail("no Sources at \(sources)") }
        var scanned = 0, hits: [String] = []
        for case let rel as String in e where rel.hasSuffix(".swift") {
            if (rel as NSString).lastPathComponent == "LegacyMigration.swift" { continue }
            let text = try String(contentsOfFile: sources + "/" + rel, encoding: .utf8)
            scanned += 1
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var l = line.lowercased()
                for a in Self.allowed { l = l.replacingOccurrences(of: a, with: "") }
                for b in Self.banned where l.contains(b) { hits.append("\(rel):\(n + 1): \(b)") }
            }
        }
        XCTAssertGreaterThan(scanned, 50)
        XCTAssertEqual(hits, [], "author-specific names in Sources:\n" + hits.joined(separator: "\n"))
    }

    /// Project-phase names and another terminal product's name stay out of the code; the author's Linear team keys
    /// stay out of string literals (comments may still cite tickets).
    func testNoPhaseNamesProductNamesOrTeamKeysInStrings() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources").path
        let fm = FileManager.default
        let phase = try NSRegularExpression(pattern: #"phase I[0-9]"#)
        let literal = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)
        let teamKeys = ["CMN-", "GBL-", "HYP-", "AGM-"]
        var hits: [String] = []
        guard let e = fm.enumerator(atPath: sources) else { return XCTFail("no Sources") }
        for case let rel as String in e where rel.hasSuffix(".swift") {
            let text = try String(contentsOfFile: sources + "/" + rel, encoding: .utf8)
            var inBlock = false
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                let where_ = "\(rel):\(n + 1)"
                if phase.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil { hits.append(where_ + ": phase name") }
                if l.contains("Warp") { hits.append(where_ + ": Warp") }
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("\"\"\"") { inBlock.toggle(); continue }
                if trimmed.hasPrefix("//") { continue }
                var strings: [String] = []
                if inBlock { strings = [l] } else {
                    for m in literal.matches(in: l, range: NSRange(l.startIndex..., in: l)) {
                        if let r = Range(m.range, in: l) { strings.append(String(l[r])) }
                    }
                }
                for str in strings { for k in teamKeys where str.contains(k) { hits.append(where_ + ": \(k) in a string") } }
            }
        }
        XCTAssertEqual(hits, [], "author-specific names in Sources:\n" + hits.joined(separator: "\n"))
    }
}

final class FolderResolutionTests: XCTestCase {
    private var tmp: String!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("neutral-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: tmp) }

    func testProjectsDefaultIsProjectsFolderIfPresentElseHome() throws {
        XCTAssertEqual(Workspace.defaultProjectsRoot(home: tmp), tmp)
        try FileManager.default.createDirectory(atPath: tmp + "/Projects", withIntermediateDirectories: true)
        XCTAssertEqual(Workspace.defaultProjectsRoot(home: tmp), tmp + "/Projects")
    }

    func testProjectsResolutionOrderEnvThenSettingThenDefault() {
        XCTAssertEqual(Workspace.resolveProjects(setting: "/s", environment: ["ONEROOF_PROJECTS": "/e"], home: tmp), "/e")
        XCTAssertEqual(Workspace.resolveProjects(setting: "/s", environment: [:], home: tmp), "/s")
        XCTAssertEqual(Workspace.resolveProjects(setting: "", environment: [:], home: tmp), tmp)
        XCTAssertEqual(Workspace.resolveProjects(setting: "~/code", environment: [:]), NSHomeDirectory() + "/code")
    }

    func testSharedResolutionOrderEnvThenSettingThenCommonUnderProjects() {
        XCTAssertEqual(Workspace.resolveShared(setting: "/s", projects: "/p", environment: ["ONEROOF_SHARED": "/e"]), "/e")
        XCTAssertEqual(Workspace.resolveShared(setting: "/s", projects: "/p", environment: [:]), "/s")
        XCTAssertEqual(Workspace.resolveShared(setting: "", projects: "/p", environment: [:]), "/p/_common")
    }

    func testConfigureMovesEveryCallSite() {
        let before = Workspace.projectsRoot
        defer { Workspace.configure(root: before) }
        Workspace.configure(root: tmp, shared: tmp + "/rules")
        XCTAssertEqual(Workspace.projectsRoot, (tmp as NSString).standardizingPath)
        XCTAssertEqual(Workspace.sharedRoot, ((tmp + "/rules") as NSString).standardizingPath)
        XCTAssertTrue(Workspace.isInsideProjects(tmp + "/a/b"))
        Workspace.configure(root: tmp)
        XCTAssertEqual(Workspace.sharedRoot, ((tmp as NSString).standardizingPath as NSString).appendingPathComponent("_common"))
    }

    func testSecondClaudeAccountOnlyWhenItsFolderExists() throws {
        XCTAssertEqual(AccountResolver.claudeAccounts(home: tmp), ["Claude1"])
        XCTAssertEqual(AccountResolver.choices(for: .claude, home: tmp), ["Claude1"])
        XCTAssertEqual(AgentMark.available([.claude1, .claude2, .codex], home: tmp), [.claude1, .codex])
        try FileManager.default.createDirectory(atPath: tmp + "/.claude-2", withIntermediateDirectories: true)
        XCTAssertEqual(AccountResolver.claudeAccounts(home: tmp), ["Claude1", "Claude2"])
        XCTAssertEqual(AgentMark.available([.claude1, .claude2, .codex], home: tmp), [.claude1, .claude2, .codex])
    }

    func testClaudeEmailIsReadFromItsConfig() throws {
        let f = tmp + "/.claude.json"
        try #"{"oauthAccount": {"emailAddress": "dev@example.com"}}"#.write(toFile: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(AccountResolver.claudeEmail(AccountResolver.claudeConfigFile("Claude1", home: tmp)), "dev@example.com")
        XCTAssertNil(AccountResolver.claudeEmail(AccountResolver.claudeConfigFile("Claude2", home: tmp)))
    }

    func testRouterNeverSuggestsAMissingSeat() {
        let policy = RoutingPolicy.load(agenticEngineering: AEFolder.bundled ?? "")
        let u = [SeatUsage(seat: "Claude1", fiveHour: 70, updated: Date()), SeatUsage(seat: "Claude2", fiveHour: 5, updated: Date())]
        let r = Router.suggest(kind: "code", usage: u, policy: policy, claudeSeats: ["Claude1"])
        XCTAssertEqual(r.agent, .claude)
        XCTAssertEqual(r.account, "Claude1")
        XCTAssertFalse(r.reason.contains("Claude2"))
        let full = [SeatUsage(seat: "Claude1", fiveHour: 99, updated: Date())]
        let r2 = Router.suggest(kind: "code", usage: full, policy: policy, claudeSeats: ["Claude1"])
        XCTAssertNotEqual(r2.account, "Claude2")
    }

    func testTrackersAreFoundWithoutADomainList() throws {
        let fm = FileManager.default
        for d in ["", "/web", "/rules"] {
            try fm.createDirectory(atPath: tmp + d, withIntermediateDirectories: true)
            try "x".write(toFile: tmp + d + "/_MASTER-TRACKER.html", atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(atPath: tmp + "/api", withIntermediateDirectories: true)
        let files = Trackers.files(projects: tmp, shared: tmp + "/rules")
        XCTAssertEqual(Set(files), Set([tmp, tmp + "/web", tmp + "/rules"].map { $0 + "/_MASTER-TRACKER.html" }))
        XCTAssertEqual(files.count, 3, "the shared tracker is listed once")
    }

    func testSoftensWorkspaceConventionsWithoutASharedFolder() {
        let r = [CheckResult(id: "memory", title: "", level: .fail, detail: ""), CheckResult(id: "herdr", title: "", level: .fail, detail: "")]
        XCTAssertEqual(Foundations.softenWithoutShared(r).map(\.level), [.warn, .fail])
    }

    func testDoorsAndMcpChecksAreOptionalWithoutSharedFolder() {
        let p = FoundationPaths(home: tmp, projects: tmp, common: tmp + "/missing", agenticEngineering: tmp)
        XCTAssertFalse(p.hasShared)
        XCTAssertEqual(Foundations.doorsCheck(p).level, .ok)
        XCTAssertEqual(Foundations.mcpCheck(p).level, .ok)
        XCTAssertTrue(Foundations.mcpCheck(p).detail.hasPrefix("optional"))
        XCTAssertEqual(Foundations.handoffs(p), [])
        XCTAssertEqual(Foundations.gotchas(p), [])
    }
}

final class RequiredToolsTests: XCTestCase {
    /// LAB-20: herdr is gone; git is the only tool One Roof needs (roofd ships inside the app).
    func testMissingGitIsRedWithAnInstallHint() {
        let r = Foundations.requiredTools(installed: { _ in false }, run: { _, _ in 1 })
        XCTAssertEqual(r.map(\.id), ["tool-git"])
        XCTAssertEqual(r.first?.level, .fail)
        XCTAssertTrue(r.first?.detail.contains("xcode-select --install") ?? false)
        XCTAssertEqual(Foundations.requiredTools(installed: { _ in false }, run: { _, _ in 0 }).map(\.level), [.ok])
    }
}

final class ReviewFamilyTests: XCTestCase {
    func testReviewAvoidsTheAuthorsVendorFamily() {
        XCTAssertEqual(AgentKind.gemini.vendorFamily, AgentKind.agy.vendorFamily)
        XCTAssertNotEqual(AgentKind.claude.vendorFamily, AgentKind.codex.vendorFamily)
        let policy = RoutingPolicy(kinds: ["review": [.init(agent: .agy, model: nil), .init(agent: .gemini, model: nil),
                                                      .init(agent: .codex, model: nil)]],
                                   skipFiveHour: 90, skipSevenDay: 95)
        XCTAssertEqual(Router.suggest(kind: "review", usage: [], policy: policy, avoid: .gemini, claudeSeats: ["Claude1"]).agent, .codex)
        XCTAssertEqual(Router.suggest(kind: "review", usage: [], policy: policy, avoid: .agy, claudeSeats: ["Claude1"]).agent, .codex)
        XCTAssertEqual(Router.suggest(kind: "review", usage: [], policy: policy, avoid: .codex, claudeSeats: ["Claude1"]).agent, .agy)
    }
}

final class SettingsDefaultsTests: XCTestCase {
    func testNewSettingsDefaultToEmptyAndDecodeFromOldJSON() throws {
        let fresh = AppSettings()
        XCTAssertEqual(fresh.projectsPath, "")
        XCTAssertEqual(fresh.commonPath, "")
        XCTAssertEqual(fresh.learnFolders, [])
        XCTAssertEqual(fresh.localModelPath, "")
        XCTAssertFalse(fresh.setupDone)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"commonPath": "/x/_common", "dockBadge": false}"#.utf8))
        XCTAssertEqual(old.commonPath, "/x/_common")
        XCTAssertFalse(old.dockBadge)
        XCTAssertEqual(old.learnFolders, [])
        XCTAssertFalse(old.setupDone)
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(round, fresh)
    }

    func testModelPathResolution() {
        XCTAssertTrue(LocalModel.defaultModelPath.hasSuffix("/One Roof/models/Qwen3-1.7B-Q4_K_M.gguf"))
        XCTAssertEqual(LocalModel.resolve(setting: "", environment: [:]), LocalModel.defaultModelPath)
        XCTAssertEqual(LocalModel.resolve(setting: "/m.gguf", environment: [:]), "/m.gguf")
        XCTAssertEqual(LocalModel.resolve(setting: "/m.gguf", environment: ["ONEROOF_MODEL": "/e.gguf"]), "/e.gguf")
        XCTAssertFalse(LocalModel.shared.installed(modelPath: "/nonexistent.gguf"))
        // A llama-server already up on the port (the owner's, or the CI Mac's) answers whatever the path; the
        // "no model, no answer" case is only checkable when nothing is listening.
        if !LocalModel.shared.healthy() {
            XCTAssertNil(LocalModel.shared.classify("fix the login bug", kinds: ["code": "write code"], modelPath: "/nonexistent.gguf"))
        }
    }
}

final class LinearKeyTests: XCTestCase {
    func testKeyOrderEnvThenOneRoofFileThenLegacy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lin-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let mine = dir + "/oneroof/linear-api-key", legacy = dir + "/legacy/api-key"
        XCTAssertNil(LinearClient.findKey(environment: [:], files: [mine, legacy]))
        try FileManager.default.createDirectory(atPath: dir + "/legacy", withIntermediateDirectories: true)
        try "old\n".write(toFile: legacy, atomically: true, encoding: .utf8)
        XCTAssertEqual(LinearClient.findKey(environment: [:], files: [mine, legacy]), "old")
        try LinearClient.saveKey("  new  ", to: mine)
        XCTAssertEqual(LinearClient.findKey(environment: [:], files: [mine, legacy]), "new")
        XCTAssertEqual(LinearClient.findKey(environment: ["LINEAR_API_KEY": "env"], files: [mine, legacy]), "env")
        let perms = try FileManager.default.attributesOfItem(atPath: mine)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testNoKeyMessageNamesEnvAndOneRoofFile() {
        let msg = LinearClient.Failure.noKey.description
        XCTAssertTrue(msg.contains("LINEAR_API_KEY"))
        XCTAssertTrue(msg.contains("~/.config/oneroof/linear-api-key"))
        XCTAssertFalse(LinearClient(key: nil).hasKey)
        XCTAssertThrowsError(try LinearClient(key: nil).workstreams())
    }
}

final class LegacyMigrationTests: XCTestCase {
    func testCopiesEveryKeyOnceAndNamesNoWorkspaceFolders() throws {
        let suite = "oneroof.tests.migration.\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { target.removePersistentDomain(forName: suite) }
        let home = "/Users/someone"
        let oldSettings = try JSONSerialization.data(withJSONObject: ["commonPath": home + "/Projects/_common", "dockBadge": false])
        let legacy: [String: Any] = ["settings": oldSettings, "grouping": "agent"]
        let present: Set<String> = [home + "/Projects/gabblegrid/gabblegrid-app/help-content"]
        XCTAssertTrue(LegacyMigration.run(target: target, legacy: legacy, home: home, exists: { present.contains($0) }))
        XCTAssertEqual(target.string(forKey: "grouping"), "agent")
        XCTAssertTrue(target.bool(forKey: LegacyMigration.flagKey))
        let s = try JSONDecoder().decode(AppSettings.self, from: XCTUnwrap(target.data(forKey: "settings")))
        XCTAssertEqual(s.projectsPath, home + "/Projects")
        XCTAssertEqual(s.commonPath, home + "/Projects/_common")
        XCTAssertEqual(s.learnFolders, [], "LAB-2140: no workspace folders filled in, even when they exist")
        XCTAssertEqual(s.localModelPath, "")
        XCTAssertFalse(s.dockBadge)
        XCTAssertTrue(s.setupDone)
        // Second run: the target already has settings, nothing is copied again.
        target.set("status", forKey: "grouping")
        XCTAssertFalse(LegacyMigration.run(target: target, legacy: legacy, home: home, exists: { _ in true }))
        XCTAssertEqual(target.string(forKey: "grouping"), "status")
    }

    func testNothingToMigrateForANewUser() throws {
        let suite = "oneroof.tests.migration.\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { target.removePersistentDomain(forName: suite) }
        XCTAssertFalse(LegacyMigration.run(target: target, legacy: nil))
        XCTAssertFalse(LegacyMigration.run(target: target, legacy: ["grouping": "agent"]))
        XCTAssertNil(target.object(forKey: "settings"))
        XCTAssertFalse(target.bool(forKey: LegacyMigration.flagKey))
    }

    func testKeepsExistingProjectsAndLearnValues() throws {
        let old = try JSONSerialization.data(withJSONObject: ["projectsPath": "/code", "learnFolders": ["/docs"]])
        let up = try XCTUnwrap(LegacyMigration.upgradedSettings(old, home: "/h", exists: { _ in true }))
        let s = try JSONDecoder().decode(AppSettings.self, from: up)
        XCTAssertEqual(s.projectsPath, "/code")
        XCTAssertEqual(s.learnFolders, ["/docs"])
        XCTAssertEqual(s.localModelPath, "", "LAB-2140: the model is found on disk or set in Settings")
    }

    /// LAB-2140 · the migration file is exempt from the neutral-source scan only for the old domain and key file; it
    /// must not name workspace folders, which would be compiled into the public download.
    func testMigrationFileNamesNoWorkspaceFolders() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/OneRoofCore/LegacyMigration.swift").path
        let text = try String(contentsOfFile: file, encoding: .utf8).lowercased()
        for b in ["gabblegrid", "hypothesys", "zibajoon", "agencium", "mindmesh", "labs-data", "labs-agentic-engineering",
                  "/labs/oneroof/", "ganarasi"] {
            XCTAssertFalse(text.contains(b), "LegacyMigration.swift names \(b)")
        }
    }
}

final class LearnFolderTests: XCTestCase {
    func testPagesAndNarrationFolders() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("learn-\(UUID().uuidString)/help-content").path
        defer { try? fm.removeItem(atPath: (root as NSString).deletingLastPathComponent) }
        for d in ["guides", "node_modules/pkg", "audio/plan", "audio/coach"] {
            try fm.createDirectory(atPath: root + "/" + d, withIntermediateDirectories: true)
        }
        try "# Start".write(toFile: root + "/getting-started.md", atomically: true, encoding: .utf8)
        try "# Deep".write(toFile: root + "/guides/deep_dive.md", atomically: true, encoding: .utf8)
        try "x".write(toFile: root + "/node_modules/pkg/README.md", atomically: true, encoding: .utf8)
        for f in ["audio/plan/intro-1.mp3", "audio/plan/next-2.mp3", "audio/coach/hello-3.mp3"] {
            try Data().write(to: URL(fileURLWithPath: root + "/" + f))
        }
        let e = LearnFolder.scan(root)
        let pages = e.filter { !$0.narration }, lists = e.filter(\.narration)
        XCTAssertEqual(Set(pages.map(\.title)), ["Getting Started", "Deep Dive"])
        XCTAssertEqual(Set(pages.map(\.section)), ["Help content"])
        XCTAssertFalse(e.contains { $0.path.contains("node_modules") })
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists.first { $0.path.hasSuffix("/plan") }?.clips, ["intro-1.mp3", "next-2.mp3"])
        XCTAssertEqual(LearnFolder.scan(root + "/missing"), [])
    }

    func testBundledHelpIsFound() throws {
        let help = try XCTUnwrap(AppResources.helpFolder, "docs/help in the checkout")
        let start = try XCTUnwrap(AppResources.helpStartPage(in: help))
        XCTAssertTrue(start.hasSuffix(".md"))
        XCTAssertNotNil(AppResources.readme)
        XCTAssertNotNil(AppResources.releaseNotes)
    }
}

final class TerminalMouseTests: XCTestCase {
    func testPlainDragSelectsAndOptionDragGoesToTheProgram() {
        XCTAssertTrue(TerminalMouse.selects(flags: []))
        XCTAssertTrue(TerminalMouse.selects(flags: [.shift]))
        XCTAssertTrue(TerminalMouse.selects(flags: [.command]))
        XCTAssertFalse(TerminalMouse.selects(flags: [.option]))
    }

    /// LAB-1554: a program with mouse reporting on gets plain clicks (Claude's "Jump to bottom"); Option selects.
    func test_LAB1554_clicksGoToAProgramThatAsksForTheMouse() {
        XCTAssertFalse(TerminalMouse.selects(flags: [], captured: true))
        XCTAssertFalse(TerminalMouse.selects(flags: [.command], captured: true))
        XCTAssertTrue(TerminalMouse.selects(flags: [.option], captured: true))
        XCTAssertTrue(TerminalMouse.selects(flags: [], captured: false))
    }

    func testDroppedPathsAreShellQuoted() {
        XCTAssertEqual(TerminalMouse.droppedPaths(["/tmp/a.txt"]), "/tmp/a.txt ")
        XCTAssertEqual(TerminalMouse.droppedPaths(["/tmp/my file.png", "/x/it's"]), "'/tmp/my file.png' '/x/it'\\''s' ")
    }

    private func pasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("oneroof-test-\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    private func tinyPNG() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPastingAScreenshotSavesItAndTypesItsPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-paste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = pasteboard()
        pb.setData(tinyPNG(), forType: .png)
        XCTAssertTrue(TerminalMouse.canPaste(pb))
        let typed = try XCTUnwrap(TerminalMouse.pasteText(from: pb, imagesDir: dir))
        let path = typed.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(path.hasPrefix(dir.path) && path.hasSuffix(".png"), typed)
        XCTAssertNotNil(NSImage(contentsOfFile: path))
    }

    func testDroppingABrowserImageTakesTheImageNotItsURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-paste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = pasteboard()
        pb.declareTypes([.png, .string], owner: nil)
        pb.setData(tinyPNG(), forType: .png)
        pb.setString("https://example.com/cat.png", forType: .string)
        XCTAssertEqual(TerminalMouse.droppedText(from: pb, save: false), "")
        let typed = try XCTUnwrap(TerminalMouse.droppedText(from: pb, imagesDir: dir))
        XCTAssertTrue(typed.hasPrefix(dir.path), typed)
        pb.clearContents()
        pb.setString("just text", forType: .string)
        XCTAssertNil(TerminalMouse.droppedText(from: pb, save: false))
    }

    func testPastingATiffImageIsSavedAsPNG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-paste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = pasteboard()
        pb.setData(NSBitmapImageRep(data: tinyPNG())!.tiffRepresentation!, forType: .tiff)
        let path = try XCTUnwrap(TerminalMouse.pasteText(from: pb, imagesDir: dir)).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testPastingTextAndFinderFiles() {
        let pb = pasteboard()
        pb.setString("hello", forType: .string)
        XCTAssertEqual(TerminalMouse.pasteText(from: pb), "hello")
        // Finder copy: a file URL plus the bare name as text → the full path wins.
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/my shot.png") as NSURL])
        XCTAssertEqual(TerminalMouse.pasteText(from: pb), "'/tmp/my shot.png' ")
        XCTAssertEqual(TerminalMouse.droppedText(from: pb), "'/tmp/my shot.png' ")
        pb.clearContents()
        XCTAssertNil(TerminalMouse.pasteText(from: pb))
        XCTAssertFalse(TerminalMouse.canPaste(pb))
    }
}
