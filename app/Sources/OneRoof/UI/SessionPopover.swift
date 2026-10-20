import SwiftUI
import OneRoofCore

/// The colourful session menu (right-click or •••): big coloured actions, stickers, colour and icon pickers.
struct SessionPopover: View {
    let item: BoardItem
    @ObservedObject var model: AppModel
    let close: () -> Void
    let rename: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var theme

    static let emojis = ["🚀", "🔥", "🐛", "🧪", "📚", "🎨", "🛠️", "💡", "⭐️", "🧠", "🔒", "📦", "💬", "🎯"]

    var live: BoardItem { model.item(item.id) ?? item }

    var body: some View {
        let it = live
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentLogo(agent: it.session.agent, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text((it.session.icon.map { $0 + " " } ?? "") + it.session.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text([it.session.agent.displayName, it.account, it.repoLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                if it.liveAgent == nil && it.status != .doNotUse {
                    tile(it.status == .exited ? "Relaunch" : "Launch", "play.fill", "mint") { model.launch(it) }
                } else if it.liveAgent != nil {
                    tile("Focus", "keyboard", "mint") { model.selectedId = it.id }
                }
                tile(it.status == .next ? "Not next" : "Next", "arrow.forward.circle.fill", "peach") { model.toggleSticker(it, "next") }
                tile(it.session.pinned ? "Unpin" : "Pin", "pin.fill", "butter") { model.togglePin(it) }
                tile("Rename", "pencil", "sky") { rename() }
                tile(it.status == .doNotUse ? "Use again" : "Do not use", "nosign", "stone") { model.toggleSticker(it, "dnu") }
                if it.liveAgent != nil {
                    tile(it.session.agent.isAgent ? "Close" : "Close", "xmark.circle.fill", "coral") { model.confirmClose(it) }
                } else if !it.adopted {
                    tile("Delete", "trash.fill", "coral") { model.delete(it) }
                }
            }

            section("STICKERS")
            StickerPicker(current: it.session.tags, soft: model.settings.stickerStyle == "soft") { model.toggleSticker(it, $0) }

            section("COLOUR")
            HStack(spacing: 7) {
                Button { model.setColor(it, nil) } label: {
                    Circle().strokeBorder(.secondary, lineWidth: 1.5).frame(width: 18, height: 18)
                        .overlay(Image(systemName: "slash.circle").font(.system(size: 10)).foregroundStyle(.secondary))
                }.buttonStyle(.plain).help("No colour")
                ForEach(Sticker.rowColors, id: \.name) { p in
                    Button { model.setColor(it, p.name) } label: {
                        Circle().fill(p.fillColor(scheme)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(p.inkColor(scheme).opacity(Pastel.named(it.session.color) == p ? 0.9 : 0.15),
                                                           lineWidth: Pastel.named(it.session.color) == p ? 2.5 : 1))
                    }.buttonStyle(.plain).help(p.name.capitalized)
                }
            }

            section("EMOJI (shown next to the name; the agent logo always stays)")
            FlowLayout(spacing: 4) {
                Button { model.setIcon(it, nil) } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 15)).frame(width: 26, height: 26).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("No emoji")
                ForEach(Self.emojis, id: \.self) { e in
                    Button { model.setIcon(it, e) } label: {
                        Text(e).font(.system(size: 17)).frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(it.session.icon == e ? Color.accentColor.opacity(0.25) : .clear))
                    }.buttonStyle(.plain)
                }
            }

            Divider()
            FlowLayout(spacing: 12) {
                link("Open repo", "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: it.session.repoPath)) }
                link("Terminal here", "terminal") { model.newTerminal(in: it.session.repoPath); close() }
                link("Copy folder", "doc.on.clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(it.session.launchDirectory, forType: .string)
                }
                if it.liveAgent != nil {
                    link("New window", "macwindow.on.rectangle") { PopOutWindowController.popOut(it, model: model); close() }
                    link("Roof window for \(it.repoLabel)", "house") { RoofWindowController.show(.repo(it.session.repoPath), model: model); close() }
                }
                if let a = it.liveAgent {
                    link("Copy attach", "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.runtime.attachCommand(a), forType: .string)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(theme.window.color)
    }

    private func tile(_ title: String, _ symbol: String, _ pastel: String, _ action: @escaping () -> Void) -> some View {
        let p = Pastel.named(pastel)!
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(title).font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(p.inkColor(scheme))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.fillColor(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.inkColor(scheme).opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
    }

    private func link(_ t: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(t, systemImage: symbol).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize() }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
    }
}

extension AppModel {
    /// Ask before ending an agent or terminal process.
    func confirmClose(_ item: BoardItem) {
        let a = NSAlert()
        a.messageText = "Close \(item.session.name)?"
        a.informativeText = item.session.agent.isAgent
            ? "This ends the agent process. Its conversation stays on disk and can be resumed later."
            : "This ends the shell."
        a.addButton(withTitle: "Close")
        a.addButton(withTitle: "Cancel")
        var review: NSButton?
        if let tk = item.session.ticket {
            let b = NSButton(checkboxWithTitle: "Comment on \(tk) and move it to In Review", target: nil, action: nil)
            b.state = .on
            a.accessoryView = b
            review = b
        }
        if a.runModal() == .alertFirstButtonReturn {
            if review?.state == .on { moveTicket(of: item.session, to: "In Review", comment: sessionSummary(item)) }
            closeAgent(item)
        }
    }
}
