import SwiftUI
import OneRoofCore

/// The v2 window: rail / icon row, session column, centre, plan, dock — driven by FocusStep (shared/FOCUS_LADDER.md).
struct V2Shell<Centre: View, Inspector: View>: View {
    @Binding var step: FocusStep
    @Binding var place: Place
    var tokens: V2Planes
    var rows: [V2SessionRow]
    var selected: String?
    var dock: V2Dock
    var window: V2WindowRef
    var onSelect: (String) -> Void
    var onNewSession: () -> Void
    var onSearch: () -> Void
    var onLook: () -> Void
    @ViewBuilder var centre: () -> Centre
    @ViewBuilder var inspector: () -> Inspector
    @State private var inspectorOver = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if step.showsRail { PlaceRail(place: $place, step: step, tokens: tokens, dock: dock, onLook: onLook) }
                if step.showsSessionColumn && place == .sessions || step == .sessions {
                    SessionsColumn(rows: rows, selected: selected, tokens: tokens, window: window, showIconRow: step.showsIconRow,
                                   place: $place, dockLine: step.showsDockLine ? dock : nil, onSelect: onSelect, onSearch: onSearch)
                        .frame(width: step == .sessions ? 280 : 250)
                }
                if step.showsAvatars { AvatarColumn(rows: rows.filter { !$0.exited }, selected: selected, tokens: tokens, onSelect: onSelect) }
                VStack(spacing: 0) {
                    V2Toolbar(step: $step, tokens: tokens, onNewSession: onNewSession)
                    centre().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(tokens.window)
                .overlay(alignment: .trailing) { if inspectorOver { inspector().frame(width: 270).background(tokens.surface).shadow(radius: 12) } }
                if step.showsInspector { Divider(); inspector().frame(width: 270).background(tokens.surface) }
                if step.showsInspectorTab { InspectorTab(tokens: tokens) { inspectorOver.toggle() } }
            }
            if step.showsDock { StatusDock(dock: dock, tokens: tokens) }
        }
        .onExitCommand { if step == .focus { step = .sessions } else { inspectorOver = false } }
    }
}

/// The four planes of a look (theme/tokens.md), resolved from the window's PanelThemes.
struct V2Planes {
    var rail: Color, sidebar: Color, window: Color, surface: Color, control: Color
    var separator: Color, separatorStrong: Color, selection: Color
    var text: Color, text2: Color, text3: Color, accent: Color, accentText: Color
    var terminal: Color, terminalHeader: Color, terminalText: Color, terminalDim: Color

    init(sidebar s: ThemeTokens, centre c: ThemeTokens, plan p: ThemeTokens, terminal t: ThemeTokens) {
        rail = s.control.color; sidebar = s.sidebar.color; window = c.window.color; surface = p.surface.color; control = s.control.color
        separator = s.separator.color; separatorStrong = s.separatorStrong.color; selection = s.surface.color
        text = c.text.color; text2 = c.text2.color; text3 = c.text3.color; accent = c.accent.color; accentText = c.accentText.color
        terminal = t.surface.color; terminalHeader = t.surface2.color; terminalText = t.text.color; terminalDim = t.text3.color
    }
    init(look: Look) {
        let pt = look.panelThemes
        self.init(sidebar: pt.sidebar.tokens, centre: pt.centre.tokens, plan: pt.plan.tokens, terminal: pt.terminal.tokens)
    }
}

struct V2Toolbar: View {
    @Binding var step: FocusStep
    var tokens: V2Planes
    var title = "Agentic engineering repo"
    var meta = "Claude1 · LAB-AGENTIC"
    @State var layout: SessionLayout = .single
    var onNewSession: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1).truncationMode(.tail)
            Text(meta).font(.system(size: 11)).foregroundStyle(tokens.text2).lineLimit(1)
            Spacer(minLength: 8)
            Picker("", selection: $layout) { ForEach(SessionLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { step = step == .focus ? .full : step.next } label: { Label(step.title, systemImage: "arrow.up.left.and.arrow.down.right") }
                .controlSize(.small).help("Focus · ⌥⌘F on, ⇧⌥⌘F back (keys live in the View menu, KeymapV2)")
            Button(action: onNewSession) { Label("New", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(tokens.separator).frame(height: 1) }
    }
}

struct InspectorTab: View {
    var tokens: V2Planes; var open: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Plan ⌥⌘P").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(-90)).fixedSize().frame(height: 70)
            Text("Ticket").font(.system(size: 10)).foregroundStyle(tokens.text2).rotationEffect(.degrees(-90)).fixedSize().frame(height: 50)
            Spacer()
        }
        .padding(.top, 14).frame(width: 28).background(tokens.surface)
        .overlay(alignment: .leading) { Rectangle().fill(tokens.separator).frame(width: 1) }
        .contentShape(Rectangle()).onTapGesture(perform: open)
    }
}
