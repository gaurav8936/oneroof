import SwiftUI
import OneRoofCore

/// What a session row shows, computed once by the model so rows stay cheap to draw (60 sessions × 6 windows).
struct RowData: Equatable, Identifiable {
    var id: String
    var name: String
    var mark: AgentMark
    var status: SessionStatus
    var caption: LiveCaption
    /// "Claude1" and "main +3 −1" (the account never truncates; the branch does).
    var account: String
    var meta: String
    var stickers: [Sticker]
    var age: String
    var unread: Bool
    var pinned: Bool
    var scheduled: String?
    var tint: Pastel?
    /// The session's own emoji (v0.1), shown before the name.
    var icon: String?
    var busy: Bool
    var ticket: String?
    var workstream: String?
    /// "3 files changed since the last commit (⌥⌘R to review)" or "Branch, nothing uncommitted".
    var branchHelp: String?
}

extension AppModel {
    func rowData(_ i: BoardItem, now: Date = Date()) -> RowData {
        var meta: [String] = []
        var help: String?
        if let st = repoStats[i.session.repoPath] {
            var b = st.branch
            if st.added > 0 || st.removed > 0 { b += " +\(st.added) −\(st.removed)" }
            else if st.files > 0 { b += " \(st.files) new" }
            meta.append(b)
            help = st.files > 0 ? "\(st.files) files changed since the last commit (⌥⌘R to review)" : "Branch, nothing uncommitted"
        } else {
            meta.append(i.repoLabel)
        }
        return RowData(id: i.id, name: i.session.name, mark: AgentMark(agent: i.session.agent, account: i.account), status: i.status,
                       caption: caption(for: i), account: i.account ?? i.session.agent.displayName, meta: meta.joined(separator: " · "),
                       stickers: Sticker.forSession(i.session, status: i.status).filter { !["next", "dnu"].contains($0.id) },
                       age: ageText(lastActiveDate(i), now: now), unread: isUnread(i), pinned: i.session.pinned,
                       scheduled: scheduleLabel(i), tint: settings.tintRows ? Pastel.named(i.session.color) : nil,
                       icon: i.session.icon, busy: busy.contains(i.id), ticket: i.session.ticket, workstream: i.session.workstream,
                       branchHelp: help)
    }
}

/// The session row (COMPONENTS SessionRow): full (Sessions panel), compact (Overview cards) or rail (folded panel).
struct SessionRow: View {
    @Environment(\.theme) private var t
    enum Density { case full, compact, rail }
    let row: RowData
    var density: Density = .full
    var selected = false
    var ring: RGB?
    var onRename: ((String) -> Void)?
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        Group {
            switch density {
            case .full: full
            case .compact: compact
            case .rail: AgentBadge(row.mark, size: 32, status: row.status, ring: ring).padding(6)
            }
        }
        .contentShape(Rectangle())
        .hoverHighlight(radius: Radius.row, selected: selected)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .fill(row.tint.map { t.sticker($0).fill.color } ?? .clear))
        // The session on screen stands out (LAB-240: a light fill alone was hard to find): accent outline and a bar
        // down the left edge.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.accent.color, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if selected {
                Capsule().fill(t.accent.color).frame(width: 4).padding(.vertical, 8).offset(x: -2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(StatusPalette.label(row.status)), \(row.caption.text)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var full: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentBadge(row.mark, size: 30, status: row.status, ring: ring)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if editing {
                        TextField("", text: $draft, onCommit: { editing = false; onRename?(draft) })
                            .textFieldStyle(.plain).ui(TypeScale.row, .semibold)
                            .onExitCommand { editing = false }
                    } else {
                        if let e = row.icon { Text(e).ui(12) }
                        Text(row.name).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                            .onTapGesture(count: 2) { guard onRename != nil else { return }; draft = row.name; editing = true }
                    }
                    if row.pinned { Text("●").ui(7).foregroundStyle(t.text3.color).accessibilityLabel("pinned") }
                    if row.unread { Circle().fill(t.accent.color).frame(width: 6, height: 6).accessibilityLabel("unread") }
                    Spacer(minLength: 4)
                    if row.busy { ProgressView().controlSize(.mini) }
                    if let s = row.scheduled { StatusPill(status: row.status, scheduled: s) }
                    else if [.next, .planned, .doNotUse].contains(row.status) { StatusPill(status: row.status) }
                    Text(row.age).ui(11).foregroundStyle(t.text3.color)
                }
                CaptionLine(caption: row.caption)
                HStack(spacing: 6) {
                    (Text(row.account).fontWeight(.semibold) + Text(" · " + row.meta))
                        .ui(10.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                        .help(row.branchHelp ?? "")
                    ForEach(row.stickers.prefix(2)) { StickerTag(sticker: $0) }
                    if row.stickers.count > 2 { Text("+\(row.stickers.count - 2)").ui(10.5).foregroundStyle(t.text3.color) }
                }
                if row.ticket != nil || row.workstream != nil {
                    HStack(spacing: 5) {
                        if let tk = row.ticket { RowChip(text: tk, strong: true) }
                        if let ws = row.workstream { RowChip(text: ws, strong: false) }
                    }
                }
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
    }

    private var compact: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentBadge(row.mark, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Spacer(minLength: 4)
                    StatusPill(status: row.status, scheduled: row.scheduled)
                }
                CaptionLine(caption: row.caption, size: 11.5)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
    }
}

/// Ticket and workstream chips on a row (v0.1): ticket filled, workstream outlined in the accent.
struct RowChip: View {
    @Environment(\.theme) private var t
    let text: String
    let strong: Bool
    var body: some View {
        Text(text).ui(10, strong ? .bold : .semibold, mono: true)
            .foregroundStyle(strong ? t.text.color : t.accentText.color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(strong ? t.text.color.opacity(0.08) : .clear))
            .overlay { if !strong { Capsule().strokeBorder(t.accent.color.opacity(0.45), lineWidth: 1) } }
            .lineLimit(1).fixedSize()
    }
}
