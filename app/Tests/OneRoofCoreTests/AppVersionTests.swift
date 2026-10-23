import XCTest
@testable import OneRoofCore

/// LAB-526: the One Roof version in every window, and roofd reporting its real version.
final class AppVersionTests: XCTestCase {
    func test_LAB526_labelFromInfoPlist() {
        let v = AppVersion(info: ["CFBundleShortVersionString": "0.4.10", "CFBundleVersion": "14"])
        XCTAssertEqual(v?.label, "One Roof 0.4.10 (14)")
        XCTAssertEqual(AppVersion(info: ["CFBundleShortVersionString": "0.5.1"])?.label, "One Roof 0.5.1")
        XCTAssertNil(AppVersion(info: [:]), "a bare swift-build binary has no version")
        XCTAssertNil(AppVersion(info: nil))
    }

    func test_LAB526_roofdFindsItsBundleInfoPlist() {
        XCTAssertEqual(AppVersion.infoPlistPath(forExecutable: "/Applications/One Roof.app/Contents/MacOS/roofd"),
                       "/Applications/One Roof.app/Contents/Info.plist")
        XCTAssertNil(AppVersion.infoPlistPath(forExecutable: "/repo/app/.build/debug/roofd"))
    }

    func test_LAB526_roofdReadsTheBundleVersion() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-ver-\(UUID().uuidString)/One Roof.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "0.5.1", "CFBundleVersion": "15"],
                                                       format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let v = AppVersion.forExecutable(macos.appendingPathComponent("roofd").path)
        XCTAssertEqual(v, AppVersion(short: "0.5.1", build: "15"))
        XCTAssertNil(AppVersion.forExecutable("/nonexistent/x/Contents/MacOS/roofd"))
    }

    func test_LAB526_checkedInInfoPlistHasAVersion() throws {
        // The Info.plist bundle.sh copies into the app (and roofd reads) carries both numbers.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let v = try XCTUnwrap(AppVersion(info: info))
        XCTAssertNotNil(AppVersion.compare(v.short, "0.0.0"))
        XCTAssertNotNil(v.build)
    }

    func test_LAB526_versionsCompareNumerically() {
        XCTAssertEqual(AppVersion.compare("0.4.9", "0.4.10"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.4.10", "0.4.10"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.5", "0.4.10"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.4", "0.4.0"), .orderedSame)
        XCTAssertNil(AppVersion.compare("dev", "0.4.10"))
    }

    func test_LAB526_olderDaemonNoteOnlyWhenOlder() {
        XCTAssertTrue(AppVersion.daemonIsOlder("0.4.0", than: "0.4.10"))
        XCTAssertNotNil(AppVersion.daemonOlderNote("0.4.0", app: "0.4.10"))
        XCTAssertNil(AppVersion.daemonOlderNote("0.4.10", app: "0.4.10"))
        XCTAssertNil(AppVersion.daemonOlderNote("0.5.0", app: "0.4.10"), "a newer daemon is not news")
        XCTAssertNil(AppVersion.daemonOlderNote("dev", app: "0.4.10"), "dev builds never warn")
        XCTAssertNil(AppVersion.daemonOlderNote("0.4.0", app: nil))
        XCTAssertNil(AppVersion.daemonOlderNote(nil, app: "0.4.10"))
    }
}
