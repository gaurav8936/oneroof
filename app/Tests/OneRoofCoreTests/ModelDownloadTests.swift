import XCTest
@testable import OneRoofCore

/// LAB-675 · Get the model: pinned file, paths, space, text, states, hashing, install, and a whole download from a
/// file:// URL (no network).
final class ModelDownloadTests: XCTestCase {
    var dir: String!

    override func setUp() {
        dir = NSTemporaryDirectory() + "oneroof-modeldl-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func test_pinnedFile() throws {
        let d = LocalModel.download
        XCTAssertEqual(d.fileName, LocalModel.modelFileName)
        XCTAssertEqual(d.url.lastPathComponent, LocalModel.modelFileName)
        XCTAssertEqual(d.url.scheme, "https")
        XCTAssertNotNil(d.url.path.range(of: #"/resolve/[0-9a-f]{40}/"#, options: .regularExpression), "a fixed revision, not main")
        XCTAssertNotNil(d.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression))
        XCTAssertEqual(d.bytes, 1_107_409_472)
        XCTAssertEqual(d.licenceFileName, "Qwen3-1.7B-LICENSE.txt")
        let lic = try XCTUnwrap(AppResources.modelLicence, "the Qwen3 licence text ships with the app")
        XCTAssertTrue(try String(contentsOfFile: lic, encoding: .utf8).contains("Apache License"))
        XCTAssertNotNil(AppResources.thirdPartyNotices)
    }

    func test_paths() {
        XCTAssertEqual(ModelDownload.partPath("/m/Q.gguf"), "/m/Q.gguf.part")
        XCTAssertEqual(ModelDownload.licencePath("/m/Q.gguf", licenceFileName: "L.txt"), "/m/L.txt")
    }

    func test_space() {
        let mb: Int64 = 1 << 20
        XCTAssertEqual(ModelDownload.bytesNeeded(total: 1000 * mb, partBytes: 0), 1000 * mb + ModelDownload.spareBytes)
        XCTAssertEqual(ModelDownload.bytesNeeded(total: 1000 * mb, partBytes: 400 * mb), 600 * mb + ModelDownload.spareBytes)
        XCTAssertEqual(ModelDownload.bytesNeeded(total: 100, partBytes: 500), ModelDownload.spareBytes)
        XCTAssertTrue(ModelDownload.hasRoom(free: 2000 * mb, total: 1000 * mb, partBytes: 0))
        XCTAssertFalse(ModelDownload.hasRoom(free: 1100 * mb, total: 1000 * mb, partBytes: 0), "needs head room")
        XCTAssertTrue(ModelDownload.hasRoom(free: 1100 * mb, total: 1000 * mb, partBytes: 500 * mb), "a .part counts")
        XCTAssertNotNil(ModelDownload.freeBytes(at: dir + "/not/yet/made"), "walks up to a folder that exists")
    }

    func test_progressText() {
        XCTAssertEqual(ModelDownload.size(1_107_409_472), "1.1 GB")
        XCTAssertEqual(ModelDownload.size(412_000_000), "412 MB")
        XCTAssertEqual(ModelDownload.size(800_000), "800 KB")
        XCTAssertEqual(ModelDownload.progressText(received: 412_000_000, total: 1_107_409_472, bytesPerSecond: nil), "412 MB of 1.1 GB · 37%")
        XCTAssertEqual(ModelDownload.progressText(received: 412_000_000, total: 1_107_409_472, bytesPerSecond: 18_000_000),
                       "412 MB of 1.1 GB · 37% · 18 MB/s · about 39 s left")
        XCTAssertEqual(ModelDownload.progressText(received: 0, total: 1_107_409_472, bytesPerSecond: 2_000_000),
                       "0 KB of 1.1 GB · 0% · 2 MB/s · about 10 min left")
    }

    func test_states() {
        typealias S = ModelDownload.State
        var s = S.idle
        s = ModelDownload.next(s, .start(alreadyHave: 0, total: 100))
        XCTAssertEqual(s, .downloading(received: 0, total: 100, bytesPerSecond: nil))
        XCTAssertEqual(ModelDownload.next(s, .start(alreadyHave: 0, total: 100)), s, "a second Start while one runs does nothing")
        s = ModelDownload.next(s, .progress(received: 40, bytesPerSecond: 10))
        XCTAssertEqual(s.fraction, 0.4)
        XCTAssertTrue(s.isBusy)
        XCTAssertEqual(ModelDownload.next(s, .cancel), .cancelled(received: 40))
        XCTAssertEqual(ModelDownload.next(.cancelled(received: 40), .progress(received: 50, bytesPerSecond: nil)), .cancelled(received: 40),
                       "a late progress after Stop is ignored")
        XCTAssertEqual(ModelDownload.next(s, .error("offline")), .failed("offline"))
        s = ModelDownload.next(s, .finishedBytes)
        XCTAssertEqual(s, .verifying)
        XCTAssertEqual(ModelDownload.next(s, .mismatch("bad")), .failed("bad"))
        XCTAssertEqual(ModelDownload.next(s, .verified(path: "/m")), .done(path: "/m"))
        XCTAssertEqual(ModelDownload.next(.failed("x"), .start(alreadyHave: 5, total: 100)), .downloading(received: 5, total: 100, bytesPerSecond: nil),
                       "Get the model again continues")
        XCTAssertEqual(ModelDownload.next(.done(path: "/m"), .reset), .idle)
        XCTAssertEqual(ModelDownload.next(.verifying, .reset), .verifying, "no reset while busy")
        XCTAssertTrue(S.cancelled(received: 2_000_000).text.contains("2 MB"))
        XCTAssertTrue(S.failed("offline").text.hasPrefix("Download failed: offline"))
        XCTAssertEqual(S.idle.text, "")
    }

    func test_hashing() throws {
        var h = ModelDownload.Hasher()
        h.update(Data("ab".utf8)); h.update(Data("c".utf8))
        XCTAssertEqual(h.hex(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256(\"abc\") across chunks")
        let f = dir + "/big.bin"
        let data = Data((0..<(9 << 20)).map { UInt8($0 % 251) })   // more than two 4 MB chunks
        try data.write(to: URL(fileURLWithPath: f))
        var whole = ModelDownload.Hasher(); whole.update(data)
        XCTAssertEqual(ModelDownload.sha256(fileAt: f), whole.hex())
        XCTAssertNil(ModelDownload.sha256(fileAt: dir + "/missing"))
        let spec = ModelDownload.Spec(url: URL(fileURLWithPath: f), sha256: whole.hex().uppercased(), bytes: Int64(data.count),
                                      fileName: "m.gguf", licenceFileName: "L.txt")
        XCTAssertNil(ModelDownload.verificationError(bytes: Int64(data.count), sha256: whole.hex(), spec: spec), "hex case does not matter")
        XCTAssertNotNil(ModelDownload.verificationError(bytes: 5, sha256: whole.hex(), spec: spec))
        XCTAssertNotNil(ModelDownload.verificationError(bytes: Int64(data.count), sha256: String(repeating: "0", count: 64), spec: spec))
    }

    func test_installMovesAndAddsLicence() throws {
        let part = dir + "/m.gguf.part", dest = dir + "/m.gguf", lic = dir + "/licence-src.txt"
        try Data("new".utf8).write(to: URL(fileURLWithPath: part))
        try Data("old".utf8).write(to: URL(fileURLWithPath: dest))
        try Data("Apache".utf8).write(to: URL(fileURLWithPath: lic))
        try ModelDownload.install(part: part, destination: dest, licenceSource: lic, licenceFileName: "L.txt")
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "new", "replaces an older file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: part))
        XCTAssertEqual(try String(contentsOfFile: dir + "/L.txt", encoding: .utf8), "Apache")
    }

    func test_offerAndSettingAfterDownload() {
        let have: Set<String> = [LocalModel.defaultModelPath, "/m/Arch-Router-1.5B-Q4_K_M.gguf", "/m/mine.gguf"]
        let exists: (String) -> Bool = { have.contains($0) }
        XCTAssertFalse(LocalModel.offerDownload(modelPath: LocalModel.defaultModelPath, exists: exists))
        XCTAssertTrue(LocalModel.offerDownload(modelPath: LocalModel.defaultModelPath, exists: { _ in false }))
        XCTAssertTrue(LocalModel.offerDownload(modelPath: "/m/Arch-Router-1.5B-Q4_K_M.gguf", exists: exists), "Arch-Router: offer the switch")
        XCTAssertFalse(LocalModel.offerDownload(modelPath: "/m/mine.gguf", exists: exists))
        XCTAssertEqual(LocalModel.settingAfterDownload("", exists: exists), "")
        XCTAssertEqual(LocalModel.settingAfterDownload("/m/Arch-Router-1.5B-Q4_K_M.gguf", exists: exists), "", "Arch-Router → the download")
        XCTAssertEqual(LocalModel.settingAfterDownload("/m/gone.gguf", exists: exists), "", "a missing file → the download")
        XCTAssertEqual(LocalModel.settingAfterDownload("/m/mine.gguf", exists: exists), "/m/mine.gguf", "your own model stays")
    }

    // MARK: The downloader, end to end from a file:// URL

    private func run(_ d: ModelDownloader, until done: @escaping (ModelDownload.State) -> Bool) -> ModelDownload.State {
        let exp = expectation(description: "download ends")
        var last = ModelDownload.State.idle
        d.onState = { s in last = s; if done(s) { exp.fulfill() } }
        d.start()
        wait(for: [exp], timeout: 20)
        return last
    }

    private func source(_ n: Int) throws -> (URL, Data) {
        let data = Data((0..<n).map { UInt8(($0 * 7) % 256) })
        let url = URL(fileURLWithPath: dir + "/source.bin")
        try data.write(to: url)
        return (url, data)
    }

    private func ended(_ s: ModelDownload.State) -> Bool {
        switch s { case .done, .failed: return true; default: return false }
    }

    func test_downloader_downloadsChecksAndInstalls() throws {
        let (url, data) = try source(3 << 20)
        var h = ModelDownload.Hasher(); h.update(data)
        let lic = dir + "/lic.txt"; try Data("Apache".utf8).write(to: URL(fileURLWithPath: lic))
        let dest = dir + "/models/m.gguf"
        let spec = ModelDownload.Spec(url: url, sha256: h.hex(), bytes: Int64(data.count), fileName: "m.gguf", licenceFileName: "m-LICENSE.txt")
        let d = ModelDownloader(spec: spec, destination: dest, licenceSource: lic)
        XCTAssertEqual(run(d, until: ended), .done(path: dest))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: dest)), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest + ".part"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/models/m-LICENSE.txt"))
        // Again: the file is already in place, so it is only checked.
        let again = ModelDownloader(spec: spec, destination: dest, licenceSource: lic)
        XCTAssertEqual(run(again, until: ended), .done(path: dest))
    }

    func test_downloader_rejectsAFileThatIsNotThePinnedOne() throws {
        let (url, data) = try source(1 << 20)
        let dest = dir + "/models/m.gguf"
        let spec = ModelDownload.Spec(url: url, sha256: String(repeating: "a", count: 64), bytes: Int64(data.count), fileName: "m.gguf",
                                      licenceFileName: "L.txt")
        let s = run(ModelDownloader(spec: spec, destination: dest, licenceSource: nil), until: ended)
        guard case let .failed(why) = s else { return XCTFail("\(s)") }
        XCTAssertTrue(why.contains("SHA-256"), why)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest + ".part"), "a bad file is not kept")
    }

    func test_downloader_continuesFromAPartFile() throws {
        let (url, data) = try source(2 << 20)
        var h = ModelDownload.Hasher(); h.update(data)
        let dest = dir + "/models/m.gguf"
        try FileManager.default.createDirectory(atPath: dir + "/models", withIntermediateDirectories: true)
        // A complete .part from an earlier try: it is hashed, not downloaded again.
        try data.write(to: URL(fileURLWithPath: dest + ".part"))
        let spec = ModelDownload.Spec(url: URL(fileURLWithPath: dir + "/nothing-here"), sha256: h.hex(), bytes: Int64(data.count),
                                      fileName: "m.gguf", licenceFileName: "L.txt")
        XCTAssertEqual(run(ModelDownloader(spec: spec, destination: dest, licenceSource: nil), until: ended), .done(path: dest))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: dest)), data)
        _ = url
    }

    func test_downloader_refusesWithoutRoom() throws {
        let spec = ModelDownload.Spec(url: URL(fileURLWithPath: dir + "/x"), sha256: String(repeating: "a", count: 64),
                                      bytes: Int64.max / 4, fileName: "m.gguf", licenceFileName: "L.txt")
        let s = run(ModelDownloader(spec: spec, destination: dir + "/models/m.gguf", licenceSource: nil), until: ended)
        guard case let .failed(why) = s else { return XCTFail("\(s)") }
        XCTAssertTrue(why.contains("free disk space"), why)
    }
}
