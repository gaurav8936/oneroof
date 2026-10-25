import SwiftUI
import OneRoofCore

/// The centre's tab strip (LAB-799): "Terminals" and one tab per open file. A file opens in its own tab, so it never
/// takes the terminals' place; they stay one click away. Shown on the terminals and on a file while any file is open.
struct CentreTabStrip: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState

    init(model: AppModel, win: WindowState) {
        self.model = model
        self.win = win
        self.state = EditorState.of(win.id)
    }

    private var front: String? { win.centre == .editor ? win.viewerPath : nil }

    var body: some View {
        if !state.tabs.isEmpty, win.centre == .workspace || win.centre == .editor {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    tab(title: "Terminals", symbol: "terminal", on: win.centre == .workspace, close: nil) { model.show(.workspace, in: win) }
                        .help("Your terminals, as you left them")
                    ForEach(state.tabs, id: \.self) { p in
                        tab(title: (p as NSString).lastPathComponent, symbol: FileKind.of(p).symbol, on: front == p, dirty: state.isDirty(p),
                            close: { win.closeTab(p) }) { win.show(path: p) }
                            .help(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
            .background(t.toolbar.color)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private func tab(title: String, symbol: String, on: Bool, dirty: Bool = false, close: (() -> Void)?, select: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).ui(11).foregroundStyle(on ? t.text.color : t.text3.color)
            Text(title).ui(12, on ? .semibold : .regular).foregroundStyle(on ? t.text.color : t.text2.color).lineLimit(1)
            if dirty { Circle().fill(t.text.color).frame(width: 6, height: 6).accessibilityLabel("unsaved") }
            if let close {
                Button(action: close) { Image(systemName: "xmark").ui(9).foregroundStyle(t.text3.color) }
                    .buttonStyle(.plain).help("Close this tab")
            }
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(on ? t.surface.color : .clear)
        .overlay(alignment: .top) { if on { Rectangle().fill(t.accent.color).frame(height: 2) } }
        .overlay(alignment: .trailing) { Rectangle().fill(t.separator.color).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}
