import AppKit
import XCTest
@testable import OneRoofCore

/// LAB-462: images pasted or dropped into the New session sheet.
final class ImageAttachmentTests: XCTestCase {
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

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-img-\(UUID().uuidString)")
    }

    func test_LAB462_openingMessageNamesTheImagesOnOneLine() {
        XCTAssertEqual(ImageAttachments.openingMessage("Fix the bug.", images: []), "Fix the bug.")
        XCTAssertEqual(ImageAttachments.openingMessage("Fix the bug.", images: ["/c/paste-1.png"]),
                       "Fix the bug. Attached image (read it): /c/paste-1.png")
        let two = ImageAttachments.openingMessage("Fix it", images: ["/c/a.png", "/c/my shot.png"])
        XCTAssertEqual(two, "Fix it Attached images (read each one): /c/a.png '/c/my shot.png'")
        XCTAssertFalse(two.contains("\n"), "typed into the agent's input box: a newline could submit early")
        XCTAssertEqual(ImageAttachments.openingMessage("  ", images: ["/c/a.png"]), "Attached image (read it): /c/a.png")
    }

    func test_LAB462_issueDescriptionEmbedsUploadsAndNamesTheRest() {
        XCTAssertEqual(ImageAttachments.issueDescription("Details", images: []), "Details")
        let d = ImageAttachments.issueDescription("Steps to reproduce", images: [
            .init(path: "/c/paste-1.png", url: "https://uploads.linear.app/x/y"),
            .init(path: "/c/paste-2.png", url: nil),
        ])
        XCTAssertEqual(d, "Steps to reproduce\n\n![paste-1.png](https://uploads.linear.app/x/y)\n\n"
                       + "Image 2 (not uploaded, on the owner's Mac): `/c/paste-2.png`")
        XCTAssertEqual(ImageAttachments.issueDescription("", images: [.init(path: "/c/a.png", url: "https://u/a")]), "![a.png](https://u/a)")
    }

    func test_LAB462_pasteAScreenshotSavesItWhereTheTerminalDoes() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = pasteboard()
        pb.setData(tinyPNG(), forType: .png)
        let paths = try XCTUnwrap(ImageAttachments.pastedImages(from: pb, imagesDir: dir))
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].hasPrefix(dir.path) && paths[0].hasSuffix(".png"))
        XCTAssertTrue((paths[0] as NSString).lastPathComponent.hasPrefix("paste-"))
        XCTAssertNotNil(NSImage(contentsOfFile: paths[0]))
    }

    func test_LAB462_textAndNonImageFilesPasteAsUsual() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = pasteboard()
        pb.setString("just text", forType: .string)
        XCTAssertNil(ImageAttachments.pastedImages(from: pb, imagesDir: dir))
        // Rich text that also carries a picture of itself stays a text paste.
        pb.clearContents()
        pb.declareTypes([.png, .string], owner: nil)
        pb.setData(tinyPNG(), forType: .png)
        pb.setString("a sentence copied from a document", forType: .string)
        XCTAssertNil(ImageAttachments.pastedImages(from: pb, imagesDir: dir))
        // An image copied from a browser (its link rides along as text) is an image.
        pb.clearContents()
        pb.declareTypes([.png, .string], owner: nil)
        pb.setData(tinyPNG(), forType: .png)
        pb.setString("https://example.com/cat.png", forType: .string)
        XCTAssertEqual(ImageAttachments.pastedImages(from: pb, imagesDir: dir)?.count, 1)
        // Files copied in Finder: only images attach; other files paste their name as usual.
        let img = dir.appendingPathComponent("shot.png"), txt = dir.appendingPathComponent("notes.txt")
        try tinyPNG().write(to: img)
        try Data("x".utf8).write(to: txt)
        pb.clearContents()
        pb.writeObjects([img as NSURL, txt as NSURL])
        XCTAssertEqual(ImageAttachments.pastedImages(from: pb, imagesDir: dir), [img.path])
        pb.clearContents()
        pb.writeObjects([txt as NSURL])
        XCTAssertNil(ImageAttachments.pastedImages(from: pb, imagesDir: dir))
    }

    func test_LAB462_droppedImageDataIsSavedAsPNG() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: tinyPNG())?.tiffRepresentation)
        let path = try XCTUnwrap(TerminalMouse.saveImage(data: tiff, in: dir))
        let saved = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertTrue(saved.starts(with: [0x89, 0x50, 0x4E, 0x47]), "converted to PNG")
        XCTAssertNil(TerminalMouse.saveImage(data: Data("not an image".utf8), in: dir))
    }

    func test_LAB462_contentTypes() {
        XCTAssertEqual(ImageAttachments.contentType(for: "/a/b.PNG"), "image/png")
        XCTAssertEqual(ImageAttachments.contentType(for: "/a/b.jpeg"), "image/jpeg")
        XCTAssertTrue(ImageAttachments.isImagePath("/a/b.HEIC"))
        XCTAssertFalse(ImageAttachments.isImagePath("/a/b.pdf"))
    }

    /// Linear's upload: fileUpload (signed URL + headers), then a PUT of the bytes; the asset URL comes back. No network.
    func test_LAB462_linearUploadUsesFileUploadThenPut() throws {
        let client = LinearClient(key: "test-key")
        var requests: [URLRequest] = []
        client.transport = { req in
            requests.append(req)
            if req.httpMethod == "PUT" { return (200, Data()) }
            let body = """
            {"data":{"fileUpload":{"success":true,"uploadFile":{"uploadUrl":"https://storage.example/put?sig=1",
             "assetUrl":"https://uploads.linear.app/a/b/c","headers":[{"key":"x-goog-meta-k","value":"v"}]}}}}
            """
            return (200, Data(body.utf8))
        }
        let png = tinyPNG()
        let url = try client.uploadFile(png, filename: "paste-1.png", contentType: "image/png")
        XCTAssertEqual(url, "https://uploads.linear.app/a/b/c")
        XCTAssertEqual(requests.count, 2)
        let q = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody ?? Data()) as? [String: Any])
        XCTAssertTrue((q["query"] as? String ?? "").contains("fileUpload"))
        let vars = q["variables"] as? [String: Any]
        XCTAssertEqual(vars?["fn"] as? String, "paste-1.png")
        XCTAssertEqual(vars?["size"] as? Int, png.count)
        let put = requests[1]
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertEqual(put.url?.absoluteString, "https://storage.example/put?sig=1")
        XCTAssertEqual(put.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(put.value(forHTTPHeaderField: "x-goog-meta-k"), "v")
        XCTAssertEqual(put.httpBody, png)
    }

    func test_LAB462_failedUploadKeepsTheLocalPath() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let img = dir.appendingPathComponent("shot.png")
        try tinyPNG().write(to: img)
        let client = LinearClient(key: "test-key")
        client.transport = { req in req.httpMethod == "PUT" ? (403, Data("denied".utf8)) : (200, Data(#"{"data":{"fileUpload":{"uploadFile":{"uploadUrl":"https://s/p","assetUrl":"https://u/a","headers":[]}}}}"#.utf8)) }
        XCTAssertEqual(client.uploadImages([img.path, dir.appendingPathComponent("gone.png").path]),
                       [.init(path: img.path, url: nil), .init(path: dir.appendingPathComponent("gone.png").path, url: nil)])
        client.transport = { req in req.httpMethod == "PUT" ? (200, Data()) : (200, Data(#"{"data":{"fileUpload":{"uploadFile":{"uploadUrl":"https://s/p","assetUrl":"https://u/a","headers":[]}}}}"#.utf8)) }
        XCTAssertEqual(client.uploadImages([img.path]), [.init(path: img.path, url: "https://u/a")])
    }
}
