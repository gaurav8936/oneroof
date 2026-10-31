import XCTest
@testable import OneRoofCore

final class HostedConnectionTests: XCTestCase {
    func connection() -> HostedConnection {
        var c = HostedConnection(name: "Together fixture", provider: .together,
                                 model: "zai-org/GLM-5.3-Flash", keyFile: "/private/key-reference.txt")
        c.priceChecked = HostedConnection.today()
        c.inputPerMillion = 0.15
        c.outputPerMillion = 0.5
        return c
    }

    func testConnectionKeepsProviderModelAndCredentialReferenceSeparate() throws {
        let c = connection()
        XCTAssertTrue(c.configurationErrors().isEmpty)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(HostedConnection.self, from: data), c)
        XCTAssertEqual(c.provider.baseURL, "https://api.together.ai/v1")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Authorization"))
    }

    func testMissingStaleOrInvalidPricingCannotBeReady() {
        var c = connection()
        c.priceChecked = "2000-01-01"
        XCTAssertFalse(c.configurationErrors().isEmpty)
        c.priceChecked = HostedConnection.today(); c.inputPerMillion = .infinity
        XCTAssertFalse(c.configurationErrors().isEmpty)
        c.inputPerMillion = 0.15; c.keyFile = "not-a-file-reference"
        XCTAssertFalse(c.configurationErrors().isEmpty)
        c.keyFile = "/private/reference"; c.model = ""
        XCTAssertFalse(c.configurationErrors().isEmpty)
    }

    func testOldAppSettingsDecodeWithoutInventingHostedAccounts() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(s.hostedConnections.isEmpty)
        XCTAssertNil(s.hostedRuntime)
        var changed = s
        let c = connection(); changed.hostedConnections = [c]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(restored.hostedConnections.first?.id, c.id)
        XCTAssertEqual(restored.hostedConnections.first?.keyFile, c.keyFile)
    }

    func testLaunchPreparationUsesPrivateReferencesAndRetainsSharedBudgetIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: root.path,
            nativeExecutables: ["goose": "/pinned/goose"], storageDirectory: root.appendingPathComponent("private").path)
        let c = connection()
        let one = try HostedPreparation.plan(connection: c, runtime: runtime, agent: .goose,
            repo: root.appendingPathComponent("repo").path, sharedDocs: root.appendingPathComponent("shared").path)
        let two = try HostedPreparation.plan(connection: c, runtime: runtime, agent: .goose,
            repo: root.appendingPathComponent("repo").path, sharedDocs: root.appendingPathComponent("shared").path)
        XCTAssertNotEqual(one.profilePath, two.profilePath)
        XCTAssertEqual(one.profile["shared_ledger"] as? String, two.profile["shared_ledger"] as? String)
        XCTAssertEqual(one.profile["key_file"] as? String, c.keyFile)
        XCTAssertEqual(one.profile["model"] as? String, c.model)
        XCTAssertEqual(one.profile["provider"] as? String, "together")
        XCTAssertTrue(one.arguments.contains("ae.hostedsession"))
        XCTAssertFalse(one.arguments.contains(c.keyFile))
        XCTAssertNil(one.environment["TOGETHER_API_KEY"])
        XCTAssertEqual(one.environment["PYTHONPATH"], root.path)
    }

    func testApplyingSetupUsesOnlyReferencesAndChecksTheHelperResponse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo"), kit = root.appendingPathComponent("kit")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: kit.appendingPathComponent("ae"), withIntermediateDirectories: true)
        try Data().write(to: kit.appendingPathComponent("ae/hostedsession.py"))
        let binary = root.appendingPathComponent("goose")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let key = root.appendingPathComponent("credential")
        try Data("fake-upstream-value-never-serialized".utf8).write(to: key)
        var c = connection(); c.keyFile = key.path
        let runtime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: kit.path,
            nativeExecutables: ["goose": binary.path], storageDirectory: root.appendingPathComponent("private").path)
        let p = try HostedPreparation.plan(connection: c, runtime: runtime, agent: .goose, repo: repo.path,
            sharedDocs: root.appendingPathComponent("shared").path)
        var calls = 0
        let ready = try HostedPreparation.apply(p) { exe, args, cwd, env in
            calls += 1
            XCTAssertEqual(exe, "/usr/bin/python3")
            XCTAssertTrue(args.contains("--prepare"))
            XCTAssertFalse(args.contains(key.path))
            XCTAssertNil(env["OPENAI_API_KEY"])
            return (0, "{\"ready\":true,\"agent\":\"goose\",\"provider\":\"together\",\"model\":\"zai-org/GLM-5.3-Flash\",\"version\":\"1.57.0\"}")
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(ready.connectionID, c.id)
        XCTAssertTrue(ready.isCurrent(connection: c, runtime: runtime))
        var repriced = c; repriced.inputPerMillion = 0.2
        XCTAssertFalse(ready.isCurrent(connection: repriced, runtime: runtime))
        var changedRuntime = runtime; changedRuntime.timeoutSeconds = 20
        XCTAssertFalse(ready.isCurrent(connection: c, runtime: changedRuntime))
        let text = try String(contentsOfFile: p.profilePath)
        XCTAssertFalse(text.contains("fake-upstream-value-never-serialized"))
        XCTAssertTrue(text.contains(key.path))
        XCTAssertFalse(try JSONEncoder().encode(ready).isEmpty)
        XCTAssertThrowsError(try HostedPreparation.apply(p) { _, _, _, _ in (0, "not a readiness response") })
        let refreshed = try HostedPreparation.refreshPrices(connection: c, runtime: runtime, repo: repo.path) { _, args, _, env in
            XCTAssertTrue(args.contains("--refresh-prices")); XCTAssertNil(env["OPENAI_API_KEY"])
            return (0, "{\"provider\":\"together\",\"model\":\"zai-org/GLM-5.3-Flash\",\"price_checked\":\"\(HostedConnection.today())\",\"unit\":\"USD per million tokens\",\"input_per_million\":0.2,\"output_per_million\":0.6}")
        }
        XCTAssertEqual(refreshed.inputPerMillion, 0.2)
        XCTAssertEqual(c.inputPerMillion, 0.15, "Refreshing a draft must not mutate the saved connection")
        XCTAssertThrowsError(try HostedPreparation.refreshPrices(connection: c, runtime: runtime, repo: repo.path) { _, _, _, _ in
            (0, "{\"provider\":\"together\",\"model\":\"wrong/model\"}")
        })
    }
}
