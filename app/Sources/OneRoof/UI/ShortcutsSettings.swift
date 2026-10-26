import AppKit
import SwiftUI
import OneRoofCore

/// Settings › Shortcuts: change any menu shortcut, and set a global shortcut that shows or hides
/// One Roof from any app. Press Record, then the new keys; Esc cancels. Duplicates are refused.
struct ShortcutsSettings: View {
    /// True while a shortcut is being recorded, so the v2 page's Esc / ⌘[ leave the key to the recorder.
    nonisolated(unsafe) static var isRecording = false
    @ObservedObject var model: AppModel
    @State private var recording: String?      // menu item title, or Self.global
    @State private var monitor: Any?
    @State private var message: String?
    @State private var filter = ""
    static let global = "\u{1}global"

    private var rows: [(menu: String, title: String)] {
        (NSApp.mainMenu?.items ?? []).flatMap { top -> [(String, String)] in
            let name = top.submenu?.title ?? ""
            return ShortcutBridge.allItems(top.submenu).filter { !$0.title.isEmpty && $0.action != nil }.map { (name.isEmpty ? "One Roof" : name, $0.title) }
        }
        .filter { filter.isEmpty || $0.1.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Show or hide One Roof from any app").font(.system(size: 12, weight: .semibold))
                Spacer()
                keyCap(Shortcut(model.settings.globalHotkey)?.display ?? "Off", recording == Self.global)
                Button(recording == Self.global ? "Press keys…" : "Record") { record(Self.global) }
                if !model.settings.globalHotkey.isEmpty { Button("Clear") { model.settings.globalHotkey = "" } }
            }
            Text("Needs ⌘, ⌥ or ⌃ (for example ⌃`). Registered with macOS; no Accessibility permission needed.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                TextField("Filter commands", text: $filter).textFieldStyle(.roundedBorder).frame(width: 220)
                Spacer()
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
                Button("Reset all") { model.settings.shortcuts = [:]; message = nil }.disabled(model.settings.shortcuts.isEmpty)
            }
            List(rows, id: \.title) { r in
                HStack {
                    Text(r.title).font(.system(size: 12))
                    Text(r.menu).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Spacer()
                    if model.settings.shortcuts[r.title] != nil {
                        Button("Reset") { model.settings.shortcuts[r.title] = nil }.controlSize(.small)
                    }
                    keyCap(current(r.title), recording == r.title)
                    Button(recording == r.title ? "Press keys…" : "Record") { record(r.title) }.controlSize(.small)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func current(_ title: String) -> String {
        guard let item = ShortcutBridge.allItems(NSApp.mainMenu).first(where: { $0.title == title }) else { return "" }
        return ShortcutBridge.shortcut(of: item)?.display ?? "—"
    }

    private func keyCap(_ text: String, _ active: Bool) -> some View {
        Text(text).font(.system(size: 11.5, design: .rounded)).frame(minWidth: 54)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
    }

    private func record(_ title: String) {
        stop()
        recording = title
        Self.isRecording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let s = ShortcutBridge.shortcut(of: e) else { return e }
            if s.key == "esc" && !s.command && !s.option && !s.control { stop(); return nil }
            accept(s, for: title)
            return nil
        }
    }

    private func accept(_ s: Shortcut, for title: String) {
        defer { stop() }
        if title == Self.global {
            guard s.isUsableGlobally else { message = "A global shortcut needs ⌘, ⌥ or ⌃."; return }
            model.settings.globalHotkey = s.display
            return
        }
        guard s.command || s.control || s.option || s.key.count > 1 else { message = "Add ⌘, ⌥ or ⌃ so typing in the terminal still works."; return }
        if let other = ShortcutBridge.owner(of: s, in: NSApp.mainMenu, except: title) {
            message = "\(s.display) is already “\(other)”."
            return
        }
        model.settings.shortcuts[title] = s.display
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        Self.isRecording = false
    }
}
