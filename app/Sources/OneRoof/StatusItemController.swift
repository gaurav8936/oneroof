import AppKit
import SwiftUI
import Combine
import OneRoofCore

/// Menu-bar extra: "● n ▶ m" — sessions that need you and sessions working. The popover lists Needs you (with
/// Allow, answered without bringing One Roof forward), Working and Tonight, and opens One Roof. Notifications need a
/// signed build and are not sent from this one.
final class StatusItemController {
    private let model: AppModel
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusPopover(model: model, close: { [weak self] in self?.popover.performClose(nil) }))
        model.$items.combineLatest(model.$decisions, model.$settings).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &bag)
    }

    private func refresh() {
        guard model.settings.menuBarExtra, !SelfTest.isActive else {
            if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
            return
        }
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self
            i.button?.action = #selector(toggle)
            item = i
        }
        let needs = max(model.openDecisionCount, model.items.filter { $0.status == .needsYou }.count)
        let working = model.items.filter { $0.status == .running }.count
        let s = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        s.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: needs > 0 ? StatusPalette.dot(.needsYou).nsColor : NSColor.secondaryLabelColor, .font: font]))
        s.append(NSAttributedString(string: "\(needs)  ▶ \(working)", attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        item?.button?.attributedTitle = s
        item?.button?.setAccessibilityLabel("One Roof: \(needs) need you, \(working) working")
    }

    @objc private func toggle() {
        guard let b = item?.button else { return }
        if popover.isShown { popover.performClose(nil) } else { popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
}

private struct StatusPopover: View {
    @ObservedObject var model: AppModel
    var close: () -> Void

    var body: some View {
        let t = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ThemeName.midnight : .daylight)
        Content(model: model, close: close).themed(t)
    }

    private struct Content: View {
        /// LAB-1338: captions redraw this view.
        @ObservedObject var engineState = EngineState.shared
        @Environment(\.theme) private var t
        @ObservedObject var model: AppModel
        var close: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                section("Needs you")
                let ds = model.openDecisions
                if ds.isEmpty && model.items.filter({ $0.status == .needsYou }).isEmpty { Text("Nothing waiting.").ui(12.5).foregroundStyle(t.text3.color) }
                ForEach(ds.prefix(5)) { d in
                    HStack(spacing: 8) {
                        if let i = model.item(d.sessionId) { AgentBadge(item: i, size: 18, status: false) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.item(d.sessionId)?.session.name ?? "").ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                            Text(d.command.map { "Run " + $0 } ?? d.headline).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                        }
                        Spacer()
                        RoofButton("Allow", .primary) { model.answer(d, .allowOnce) }
                        RoofButton("Open") { open(d.sessionId) }
                    }
                }
                section("Working")
                ForEach(model.items.filter { $0.status == .running }.prefix(6)) { i in
                    Button { open(i.id) } label: {
                        HStack(spacing: 8) {
                            AgentBadge(item: i, size: 18, status: false)
                            Text(i.session.name).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                            Spacer()
                            Text(model.caption(for: i).text).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).frame(maxWidth: 160, alignment: .trailing)
                        }
                    }.buttonStyle(.plain)
                }
                if !model.schedules.isEmpty {
                    section("Tonight")
                    ForEach(model.items.filter { model.schedules[$0.id] != nil }) { i in
                        HStack { Text(i.session.name).ui(12.5).foregroundStyle(t.text.color); Spacer(); Text(model.schedules[i.id] ?? "").ui(11.5).foregroundStyle(t.text3.color) }
                    }
                }
                Hairline()
                Button { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil); close() } label: {
                    Text("Open One Roof").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
                }.buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 360)
            .background(t.window.color)
        }

        private func section(_ s: String) -> some View { MicroLabel(s) }

        private func open(_ id: String) {
            NSApp.activate(ignoringOtherApps: true)
            if let i = model.item(id) { model.reveal(i) }
            close()
        }
    }
}
