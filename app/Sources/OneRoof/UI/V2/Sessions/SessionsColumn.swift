import SwiftUI
import OneRoofCore

struct SessionsColumn: View {
    var rows: [V2SessionRow]
    var selected: String?
    var tokens: V2Planes
    var window: V2WindowRef
    var showIconRow: Bool
    @Binding var place: Place
    var dockLine: V2Dock?
    var onSelect: (String) -> Void
    var onSearch: () -> Void
    @State private var filter = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showIconRow { PlacesIconRow(place: $place, tokens: tokens, needsYou: dockLine?.needsYou ?? 0) } else { Color.clear.frame(height: 12) }
            WindowSwitcher(window: window, tokens: tokens).padding(.horizontal, 10).padding(.bottom, 8)
            Button(action: onSearch) {
                HStack { Text("Search, or ask how do I…"); Spacer(); Text("⌘K").font(.system(size: 10)) }
                    .font(.system(size: 12)).foregroundStyle(tokens.text2).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tokens.control))
            }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 8)
            HStack(spacing: 4) {
                ForEach(["All", "Need you", "Active", "Exited"], id: \.self) { f in
                    Text(f).font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Capsule().fill(f == filter ? tokens.text : tokens.control))
                        .foregroundStyle(f == filter ? tokens.window : tokens.text)
                        .onTapGesture { filter = f }
                }
                Spacer()
                Menu("Status") { ForEach(["Status", "Repo", "Project", "Agent", "Account", "Folder"], id: \.self) { Button($0) {} } }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 10))
            }.padding(.horizontal, 12).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered.filter { !$0.exited }) { r in row(r) }
                    let ex = filtered.filter(\.exited)
                    if !ex.isEmpty {
                        Text("EXITED · \(ex.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(tokens.text2).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 3)
                        ForEach(ex) { r in row(r).opacity(0.6) }
                    }
                }.padding(.horizontal, 6)
            }
            if let d = dockLine { DockLine(dock: d, tokens: tokens) }
        }
        .background(tokens.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(tokens.separator).frame(width: 1) }
    }

    private var filtered: [V2SessionRow] {
        switch filter {
        case "Need you": return rows.filter { $0.status == .needsYou }
        case "Active": return rows.filter { [.running, .needsYou, .done, .idle].contains($0.status) }
        case "Exited": return rows.filter(\.exited)
        default: return rows
        }
    }

    private func row(_ r: V2SessionRow) -> some View {
        HStack(alignment: .top, spacing: 9) {
            V2AgentBadge(text: r.badge, color: r.badgeColor, status: r.status, ring: tokens.sidebar)
            VStack(alignment: .leading, spacing: 1) {
                HStack { Text(r.title).font(.system(size: 12, weight: .semibold)).lineLimit(1); Spacer(); Text(r.slot.map { "⌘\($0)" } ?? r.age).font(.system(size: 10)).foregroundStyle(tokens.text3) }
                Text(r.statusLine).font(.system(size: 11)).foregroundStyle(r.status == .running ? tokens.accent : r.status == .done ? Color(.systemGreen) : tokens.text2).lineLimit(1)
                Text(r.meta).font(.system(size: 10)).foregroundStyle(tokens.text3).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(r.id == selected ? tokens.selection : .clear).shadow(color: .black.opacity(r.id == selected ? 0.1 : 0), radius: 1, y: 1))
        .contentShape(Rectangle()).onTapGesture { onSelect(r.id) }
        .contextMenu { V2SessionContextMenu() }
    }
}

struct V2AgentBadge: View {
    var text: String; var color: Color; var status: SessionStatus; var ring: Color; var size: CGFloat = 24
    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .bold)).foregroundStyle(text == "C2" || text == ">_" ? .black : .white)
            .frame(width: size, height: size).background(RoundedRectangle(cornerRadius: 7).fill(color))
            .overlay(alignment: .bottomTrailing) { Circle().fill(StatusPalette.dot(status).color).frame(width: 8, height: 8).overlay(Circle().stroke(ring, lineWidth: 2)).offset(x: 2, y: 2) }
    }
}

struct AvatarColumn: View {
    var rows: [V2SessionRow]; var selected: String?; var tokens: V2Planes; var onSelect: (String) -> Void
    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 40)
            ForEach(rows) { r in
                V2AgentBadge(text: r.badge, color: r.badgeColor, status: r.status, ring: tokens.sidebar, size: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(r.id == selected ? tokens.accent : .clear, lineWidth: 2))
                    .onTapGesture { onSelect(r.id) }.help(r.title)
            }
            Spacer()
        }.frame(width: 52).background(tokens.sidebar)
    }
}

struct WindowSwitcher: View {
    var window: V2WindowRef; var tokens: V2Planes
    var body: some View {
        Menu {
            Button("New window ⇧⌘N") {}; Button("New window for this repo ⌥⌘N") {}; Button("Rename window…") {}
            Menu("Window colour") { ForEach(["Gold", "Blue", "Green", "Purple"], id: \.self) { Button($0) {} } }
            Button("Show all windows on the Wall") {}  // Move to iPad hidden until the iPad app exists (LAB-1189)
        } label: {
            HStack(spacing: 7) {
                Circle().fill(window.color).frame(width: 8, height: 8)
                Text(window.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("1 of 3 ▾").font(.system(size: 10)).foregroundStyle(tokens.text3)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surface).shadow(color: .black.opacity(0.08), radius: 1, y: 1))
        }.menuStyle(.borderlessButton)
    }
}

/// Session menu (A10.4) — same actions as the Session menu bar menu.
struct V2SessionContextMenu: View {
    var body: some View {
        Button("Launch") {}; Button("Interrupt") {}; Button("Send Handoff") {}
        Divider()
        Button("Mark as Next") {}; Button("Mark as Planned") {}
        Menu("Schedule") { Button("Tonight") {}; Button("Tomorrow 9:00") {} }
        Button("Run Now") {}; Button("Pin") {}; Button("Rename…") {}
        Menu("Move to Window") { Button("Window 2") {}; Button("Window 3") {} }
        Button("Open in New Window") {}
        Divider()
        Button("Open Repo in Finder") {}; Button("Copy Session ID") {}; Button("Copy Attach Command") {}; Button("Copy Link to Session") {}
        Divider()
        Button("Do Not Use") {}; Button("Close Agent…") {}; Button("Delete Session", role: .destructive) {}
    }
}
