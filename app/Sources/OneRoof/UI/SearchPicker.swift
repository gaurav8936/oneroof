import OneRoofCore
import SwiftUI

/// LAB-1559: a picker with a search field (New session: Team, Project). Click opens it with the field focused; typing
/// narrows the list (every word, any order); ↑ ↓ move, Return picks, Esc closes. `top` and `bottom` hold the fixed
/// choices ("No project", "New project…"), which stay visible while searching.
struct SearchPicker<Label: View>: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let action: () -> Void
    }

    let prompt: String
    let rows: [Row]
    var top: [Row] = []
    var bottom: [Row] = []
    /// LAB-1571: an "Active only" switch above the list (nil = none).
    var activeOnly: Binding<Bool>? = nil
    /// Self-test: open the list once the sheet is up.
    var openOnAppear = false
    @ViewBuilder let label: () -> Label
    @Environment(\.theme) private var t
    @State private var open = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var shown: [Row] { top + PickerSearch.filter(rows, query: query, text: \.title) + bottom }

    var body: some View {
        Button { query = ""; highlighted = 0; open = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) { panel }
            .onAppear { if openOnAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { open = true } } }
    }

    private var panel: some View {
        let list = shown
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain).ui(12.5).padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separator.color))
                .focused($focused)
                .onChange(of: query) { _, _ in highlighted = list.isEmpty ? 0 : min(top.count, list.count - 1) }
                .onSubmit { pick(list) }
                .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(list.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                .accessibilityLabel(prompt)
                if let activeOnly {
                    Toggle("Active only", isOn: activeOnly).toggleStyle(.checkbox).ui(12)
                        .help("Only projects Linear has In Progress")
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, row in
                            Button { row.action(); open = false } label: {
                                Text(row.title).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                                        .fill(i == highlighted ? t.selection.color : .clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(i)
                            .onHover { if $0 { highlighted = i } }
                        }
                        if list.count == top.count + bottom.count, !query.isEmpty {
                            Text("Nothing matches “\(query)”").ui(12).foregroundStyle(t.text2.color).padding(8)
                        }
                    }
                }
                .onChange(of: highlighted) { _, i in proxy.scrollTo(i) }
            }
            .frame(maxHeight: 360)
        }
        .padding(10)
        .frame(width: 460)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func pick(_ list: [Row]) {
        guard list.indices.contains(highlighted) else { return }
        list[highlighted].action()
        open = false
    }
}
