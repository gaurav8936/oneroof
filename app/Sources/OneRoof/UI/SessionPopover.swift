import SwiftUI
import OneRoofCore

/// The colourful session menu (•••, or "Emoji, New Sticker and Rename…" on right-click): big coloured actions, stickers,
/// colour and emoji. Folder, terminal and window actions live in the right-click menu only (LAB-257).
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
                    tile(it.status == .exited ? "Relaunch" : "Launch", "play.fill", "mint", help: "Start the agent in this session") { model.launch(it) }
                } else if it.liveAgent != nil {
                    tile("Open", "rectangle.and.hand.point.up.left.fill", "mint", help: "Show this session in the main pane") { model.reveal(it); close() }
                }
                tile(it.status == .next ? "Not next" : "Next", "arrow.forward.circle.fill", "peach", help: "Scheduling: mark it as the one to do next (the Next sticker)") { model.toggleSticker(it, "next") }
                tile(it.session.pinned ? "Unpin" : "Pin", "pin.fill", "butter", help: "Keep it in the Pinned group at the top") { model.togglePin(it) }
                tile("Rename", "pencil", "sky", help: "Change the session's name") { rename() }
                tile(it.status == .doNotUse ? "Use again" : "Do not use", "nosign", "stone", help: "Park it: kept, but struck through") { model.toggleSticker(it, "dnu") }
                if it.liveAgent != nil {
                    tile("Close", "xmark.circle.fill", "coral", help: "End the agent or shell (asks first)") { model.confirmClose(it) }
                } else if !it.adopted {
                    tile("Delete", "trash.fill", "coral", help: "Remove this session from One Roof") { model.delete(it) }
                }
            }

            section("STICKERS")
            StickerPicker(current: it.session.tags, soft: model.settings.stickerStyle == "soft") { model.toggleSticker(it, $0) }

            section("COLOUR")
            HStack(spacing: 7) {
                Button { model.setColor(it, nil) } label: { ColourSwatch(pastel: nil, selected: Pastel.named(it.session.color) == nil, size: 20) }
                    .buttonStyle(.plain).help("No colour")
                ForEach(Sticker.rowColors, id: \.name) { p in
                    Button { model.setColor(it, p.name) } label: { ColourSwatch(pastel: p, selected: Pastel.named(it.session.color) == p, size: 20) }
                        .buttonStyle(.plain).help(p.name.capitalized + " row")
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
        }
        .padding(14)
        .frame(width: 330)
        .background(theme.window.color)
    }

    private func tile(_ title: String, _ symbol: String, _ pastel: String, help: String, _ action: @escaping () -> Void) -> some View {
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
        .help(help)
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
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
