import XCTest
import AppKit

/// LAB-1281: a main window's frame is remembered between launches. 1.9.2 named the frame on the window before handing
/// it to NSWindowController, which replaced the name with its own empty one: no main window's frame was ever saved, so
/// every launch (and every release install) opened each window at the first-launch default size, 1700 × 1000.
final class WindowFrameMemoryTests: XCTestCase {

    /// The AppKit behaviour behind the bug, pinned: a name set on the window before the controller is lost; the
    /// controller's own `windowFrameAutosaveName` sticks.
    @MainActor
    func test_LAB1281_controllerKeepsOnlyItsOwnAutosaveName() {
        let name = "OneRoofTest.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame " + name) }

        let before = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        before.setFrameAutosaveName(name)
        let lost = NSWindowController(window: before)
        XCTAssertEqual(lost.window?.frameAutosaveName, "", "AppKit drops a name set before NSWindowController(window:)")
        lost.close()

        let after = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let kept = NSWindowController(window: after)
        kept.windowFrameAutosaveName = name
        XCTAssertEqual(kept.window?.frameAutosaveName, name)
        kept.close()
    }

    /// The main window names its frame through the controller, after `super.init(window:)`.
    func test_LAB1281_mainWindowNamesItsFrameAfterTheController() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OneRoof/MainWindowController.swift")
        let src = try String(contentsOf: file, encoding: .utf8)
        let initCall = try XCTUnwrap(src.range(of: "super.init(window: window)"))
        let named = try XCTUnwrap(src.range(of: "windowFrameAutosaveName = autosave"), "the frame is named on the controller")
        XCTAssertLessThan(initCall.lowerBound, named.lowerBound)
        XCTAssertNil(src.range(of: "window.setFrameAutosaveName("), "a name set on the window is replaced by the controller's")
        XCTAssertNotNil(src.range(of: "shouldCascadeWindows = false"))
    }
}
