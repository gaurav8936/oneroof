import XCTest
@testable import OneRoofCore

/// LAB-1930 · the verified open-weight coding model list per provider and how a session picks from it.
final class HostedModelListTests: XCTestCase {
    func connection(_ p: HostedProvider = .together) -> HostedConnection {
        var c = HostedConnection(name: "fixture", provider: p, model: p.testedModel, keyFile: "/private/key-reference.txt")
        c.priceChecked = HostedConnection.today(); c.inputPerMillion = 0.15; c.outputPerMillion = 0.5
        c.sessionBudgetUSD = 1; c.sharedBudgetUSD = 10
        return c
    }

    func testEveryProviderOffersVerifiedModelsWithDatedPositivePrices() {
        for p in HostedProvider.allCases {
            XCTAssertFalse(p.verifiedModels.isEmpty, "\(p) has no verified model")
            XCTAssertEqual(p.testedModel, p.verifiedModels.first?.id)
            XCTAssertEqual(Set(p.verifiedModels.map(\.id)).count, p.verifiedModels.count, "duplicate ids for \(p)")
            for m in p.verifiedModels {
                XCTAssertEqual(m.provider, p)
                XCTAssertTrue(m.id.contains("/") && !m.id.contains(" "), m.id)
                XCTAssertTrue(m.inputPerMillion > 0 && m.outputPerMillion > 0, m.id)
                XCTAssertNotNil(DateFormatter.iso.date(from: m.verified), m.verified)
                XCTAssertTrue(m.priceSource.hasPrefix("https://"), m.priceSource)
                XCTAssertFalse(m.displayName.isEmpty)
            }
        }
    }

    func testChoosingAVerifiedModelKeepsKeyCeilingsAndSharedLedgerButTakesItsPrices() throws {
        let c = connection()
        XCTAssertEqual(c.choosing(model: c.model), c, "the connection's own model is the connection itself")
        guard let other = HostedProvider.together.verifiedModels.first(where: { $0.id != c.model }) else { return }
        let chosen = try XCTUnwrap(c.choosing(model: other.id))
        XCTAssertEqual(chosen.model, other.id)
        XCTAssertEqual(chosen.inputPerMillion, other.inputPerMillion)
        XCTAssertEqual(chosen.outputPerMillion, other.outputPerMillion)
        XCTAssertEqual(chosen.priceSource, other.priceSource)
        XCTAssertEqual(chosen.id, c.id, "same connection id = same shared ledger")
        XCTAssertEqual(chosen.keyFile, c.keyFile)
        XCTAssertEqual(chosen.sessionBudgetUSD, 1); XCTAssertEqual(chosen.sharedBudgetUSD, 10)
        XCTAssertEqual(chosen.priceChecked, c.priceChecked)
        XCTAssertTrue(chosen.configurationErrors().isEmpty)
        XCTAssertEqual(c.sessionModels.first, c.model)
        XCTAssertTrue(c.sessionModels.contains(other.id))
    }

    func testUnknownOrOtherProvidersModelsAreRefused() {
        let c = connection()
        XCTAssertNil(c.choosing(model: nil))
        XCTAssertNil(c.choosing(model: ""))
        XCTAssertNil(c.choosing(model: "acme/closed-model"))
        if let fw = HostedProvider.fireworks.verifiedModels.first { XCTAssertNil(c.choosing(model: fw.id)) }
        XCTAssertNil([c].resolved(id: "missing", model: c.model))
        XCTAssertEqual([c].resolved(id: c.id, model: c.model), c)
    }

    func testLaunchPlanUsesTheChosenModelAndItsPrices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runtime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: root.path,
            nativeExecutables: ["opencode": "/pinned/opencode"], storageDirectory: root.appendingPathComponent("private").path)
        guard let other = HostedProvider.together.verifiedModels.first(where: { $0.id != connection().model }) else { return }
        let c = try XCTUnwrap(connection().choosing(model: other.id))
        let plan = try HostedPreparation.plan(connection: c, runtime: runtime, agent: .opencode,
            repo: root.appendingPathComponent("repo").path, sharedDocs: root.appendingPathComponent("shared").path)
        XCTAssertEqual(plan.profile["model"] as? String, other.id)
        XCTAssertEqual(plan.profile["input_per_million"] as? Double, other.inputPerMillion)
        XCTAssertTrue((plan.profile["shared_ledger"] as? String ?? "").contains("/connections/" + c.id + "/"))
    }

    /// The help page's table and the app's list are the same rows (docs/help/hosted-agents.md § Verified models).
    func testHelpPageTableMatchesTheVerifiedList() throws {
        let doc = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../docs/help/hosted-agents.md")
        let text = try String(contentsOf: doc.standardizedFileURL, encoding: .utf8)
        var rows = Set<String>()
        for line in text.split(separator: "\n") where line.hasPrefix("| ") && line.contains("`") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 6, let p = HostedProvider.allCases.first(where: { $0.displayName == cells[1] }) else { continue }
            rows.insert("\(p.rawValue) \(cells[2].replacingOccurrences(of: "`", with: "")) \(cells[3]) \(cells[4]) \(cells[5])")
        }
        let expected = Set(HostedModel.verified.map {
            "\($0.provider.rawValue) \($0.id) \(Self.usd($0.inputPerMillion)) \(Self.usd($0.outputPerMillion)) \($0.verified)" })
        XCTAssertEqual(rows, expected)
    }

    static func usd(_ v: Double) -> String { "$" + String(format: "%g", v) }
}

private extension DateFormatter {
    static let iso: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
}
