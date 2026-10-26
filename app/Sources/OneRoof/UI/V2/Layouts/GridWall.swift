import SwiftUI
import OneRoofCore

struct V2Tile: Identifiable { var id: String; var title: String; var agent: String; var status: SessionStatus; var state: String; var rightNow: String; var window: String }

/// Grid (A4.1) and Wall (A4.2). `terminal(id)` returns the live libghostty view for that session.
struct TileGrid<T: View>: View {
    var tiles: [V2Tile]; var columns: Int; var focused: String?; var showComposer: Bool; var tokens: V2Planes
    var onFocus: (String) -> Void; var onOpen: (String) -> Void
    @ViewBuilder var terminal: (String) -> T
    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(tiles) { t in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(StatusPalette.dot(t.status).color).frame(width: 7, height: 7)
                        Text(t.title).bold().lineLimit(1); Text(t.agent).foregroundStyle(tokens.terminalDim)
                        Spacer(); Text(t.state).foregroundStyle(tokens.terminalDim)
                    }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 6).background(tokens.terminalHeader)
                    Text(t.rightNow).font(.system(size: 11)).foregroundStyle(tokens.accentText).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 6)
                    terminal(t.id).frame(minHeight: 160)
                    if showComposer { Text("Message \(t.agent)…").font(.system(size: 10.5)).foregroundStyle(tokens.terminalDim).frame(maxWidth: .infinity, alignment: .leading).padding(6).background(RoundedRectangle(cornerRadius: 7).fill(tokens.terminalHeader)).padding(6) }
                }
                .foregroundStyle(tokens.terminalText).background(tokens.terminal)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(t.id == focused ? tokens.accent : .clear, lineWidth: 2))
                .onTapGesture { onFocus(t.id) }.onTapGesture(count: 2) { onOpen(t.id) }
            }
        }.padding(10)
    }
}

/// Wall: every window, grouped (A4.2).
struct WallView<T: View>: View {
    var groups: [(window: V2WindowRef, tiles: [V2Tile])]; var tokens: V2Planes; var onOpen: (String) -> Void
    @ViewBuilder var terminal: (String) -> T
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.window.id) { g in
                    HStack(spacing: 8) { Circle().fill(g.window.color).frame(width: 9, height: 9); Text(g.window.name).bold(); Text(g.window.state).foregroundStyle(tokens.text3) }.font(.system(size: 12))
                    TileGrid(tiles: g.tiles, columns: 5, focused: nil, showComposer: false, tokens: tokens, onFocus: { _ in }, onOpen: onOpen, terminal: terminal)
                }
            }.padding(12)
        }
    }
}
