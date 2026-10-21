import SwiftUI
import OneRoofCore

/// The colourful session menu (•••, or "Emoji, New Sticker and Rename…" on right-click). LAB-300: everything is one
/// click, nothing hides behind another: compact action buttons in a wrapping row (no Close here; it is on the
/// right-click menu and the row's ✕), sticker chips (labels only; the meaning is a tooltip), colour swatches (names
/// only in the tooltip and VoiceOver), and the emoji. Folder, terminal and window actions live in the right-click
/// menu only (LAB-257).
struct SessionPopover: View {
    let item: BoardItem
    @ObservedObject var model: AppModel
    let close: () -> Void
    let rename: () -> Void
    /// Opens the Attach issue sheet (LAB-474); the hosts close the popover and select the session first.
    var attachIssue: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var theme

    static var emojis: [String] { Sticker.emojiChoices }

    var live: BoardItem { model.item(item.id) ?? item }

    var body: some View {
        let it = live
        let tagIds = Set(it.session.tags.map { Sticker.resolve($0).id })
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentLogo(agent: it.session.agent, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text((it.session.icon.map { $0 + " " } ?? "") + it.session.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text([it.session.agent.displayName, it.account, it.repoLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(theme.text2.color).lineLimit(1)
                }
            }

            FlowLayout(spacing: 6) {
                ForEach(SessionQuickAction.available(for: it), id: \.self) { a in
                    actionButton(a, it, tagIds: tagIds)
                }
            }

            section("STICKERS")
            StickerPicker(current: it.session.tags, soft: model.settings.stickerStyle == "soft") { model.toggleSticker(it, $0) }

            section("COLOUR")
            HStack(spacing: 4) {
                Button { model.setColor(it, nil) } label: { ColourSwatch(pastel: nil, selected: Pastel.named(it.session.color) == nil, size: 17) }
                    .buttonStyle(.plain).help("No colour").accessibilityLabel("No row colour")
                ForEach(Sticker.rowColors, id: \.name) { p in
                    Button { model.setColor(it, p.name) } label: { ColourSwatch(pastel: p, selected: Pastel.named(it.session.color) == p, size: 17) }
                        .buttonStyle(.plain).help(p.name.capitalized + " row").accessibilityLabel(p.name.capitalized + " row colour")
                }
            }

            section("EMOJI").help("Shown next to the name; the agent logo always stays")
            FlowLayout(spacing: 3) {
                Button { model.setIcon(it, nil) } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 14)).frame(width: 26, height: 26)
                        .foregroundStyle(theme.text2.color)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(it.session.icon == nil ? theme.selection.color : .clear))
                }.buttonStyle(.plain).help("No emoji").accessibilityLabel("No emoji")
                ForEach(Self.emojis, id: \.self) { e in
                    Button { model.setIcon(it, e) } label: {
                        Text(e).font(.system(size: 16)).frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(it.session.icon == e ? theme.selection.color : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(it.session.icon == e ? theme.accent.color : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Emoji \(e)")
                    .accessibilityAddTraits(it.session.icon == e ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(theme.window.color)
    }

    @ViewBuilder
    private func actionButton(_ a: SessionQuickAction, _ it: BoardItem, tagIds: Set<String>) -> some View {
        switch a {
        case .launch, .relaunch:
            chip(a == .relaunch ? "Relaunch" : "Launch", "play.fill", "mint", help: "Start the agent in this session") { model.launch(it) }
        case .open:
            chip("Open", "rectangle.and.hand.point.up.left.fill", "mint", help: "Show this session in the main pane") { model.reveal(it); close() }
        case .next:
            chip("Next", "arrow.forward.circle.fill", "peach", on: it.status == .next || tagIds.contains("next"),
                 help: "Scheduling: mark it as the one to do next (the Next sticker)") { model.toggleSticker(it, "next") }
        case .pin:
            chip("Pin", "pin.fill", "butter", on: it.session.pinned, help: "Keep it in the Pinned group at the top") { model.togglePin(it) }
        case .rename:
            chip("Rename", "pencil", "sky", help: "Change the session's name") { rename() }
        case .issue:
            chip(it.session.ticket == nil ? "Issue…" : "Change issue…", "link", "lavender",
                 help: "Attach a Linear issue to this session: an open one, or a new one") { attachIssue() }
        case .highlight:
            chip("Highlight", "star.fill", "coral", on: tagIds.contains(Sticker.highlightId),
                 help: "Priority: mark it Important (the Important sticker)") { model.toggleSticker(it, Sticker.highlightId) }
        case .doNotUse:
            chip("Do not use", "nosign", "stone", on: it.status == .doNotUse, help: "Park it: kept, but struck through") { model.toggleSticker(it, "dnu") }
        case .delete:
            chip("Delete", "trash.fill", "coral", help: "Remove this session from One Roof (⇧⌘T reopens it)") { model.delete(it) }
        }
    }

    /// A compact action button. `on == nil`: a plain action (filled). Toggles are filled when on, outlined when off.
    private func chip(_ title: String, _ symbol: String, _ pastel: String, on: Bool? = nil, help: String,
                      _ action: @escaping () -> Void) -> some View {
        let p = Pastel.named(pastel)!
        let filled = on ?? true
        // Off toggles are an outline in their own colour (like an unchosen sticker): ink on light panels, pastel on dark.
        let edge = filled ? p.inkColor(scheme).opacity(0.12) : (scheme == .dark ? p.fillColor(scheme).opacity(0.8) : p.inkColor(scheme).opacity(0.5))
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .bold))
                Text(title).font(.system(size: 11.5, weight: .bold, design: .rounded)).lineLimit(1)
                if on == true { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
            }
            .foregroundStyle(filled ? p.inkColor(scheme) : (scheme == .dark ? p.fillColor(scheme) : p.inkColor(scheme)))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(filled ? p.fillColor(scheme) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(edge, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title + (on == nil ? "" : (on! ? ", on" : ", off")))
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(theme.text2.color)
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
