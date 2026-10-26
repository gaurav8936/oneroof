import SwiftUI
import OneRoofCore

/// Panel layout for Settings, Foundations, Setup, Help and every second-level screen (C*):
/// kicker, title, subtitle, actions, then a grid of blocks with rows or text.
struct PanelSpec {
    struct V2Action: Identifiable { var id: String { title }; var title: String; var primary = false; var run: () -> Void = {} }
    struct V2Row: Identifiable {
        enum Lead { case ok, issue, off, dot, badge(String, Color) }
        var id = UUID(); var lead: Lead = .dot; var title: String; var detail = ""; var value = ""
        var action: String? = nil; var selected = false; var mono = false; var run: () -> Void = {}
    }
    struct V2Block: Identifiable { var id = UUID(); var title = ""; var rows: [V2Row] = []; var text: [String] = []; var mono = false }
    var kicker: String; var title: String; var subtitle = ""; var actions: [V2Action] = []
    var columns = 1; var leading: V2Block? = nil; var blocks: [V2Block]
}

struct PanelView: View {
    var spec: PanelSpec; var tokens: V2Planes
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.kicker).font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.accentText)
                    Text(spec.title).font(.system(size: 24, weight: .bold))
                    if !spec.subtitle.isEmpty { Text(spec.subtitle).foregroundStyle(tokens.text2) }
                }
                Spacer()
                ForEach(spec.actions) { a in
                    if a.primary { Button(a.title, action: a.run).buttonStyle(.borderedProminent) } else { Button(a.title, action: a.run) }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if let l = spec.leading { block(l).frame(width: 220) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: spec.columns), alignment: .leading, spacing: 12) {
                    ForEach(spec.blocks) { block($0) }
                }
            }
            Spacer(minLength: 0)
        }.font(.system(size: 12)).padding(16)
    }

    private func block(_ b: PanelSpec.V2Block) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !b.title.isEmpty { Text(b.title).font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3) }
            ForEach(b.rows) { r in
                HStack(spacing: 10) {
                    lead(r.lead)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).fontWeight(r.selected ? .bold : .semibold).lineLimit(1)
                        if !r.detail.isEmpty { Text(r.detail).font(.system(size: 11)).foregroundStyle(tokens.text2) }
                    }
                    Spacer()
                    if !r.value.isEmpty { Text(r.value).font(.system(size: 11.5, design: r.mono ? .monospaced : .default)).foregroundStyle(tokens.text2) }
                    if let a = r.action { Button(a, action: r.run).controlSize(.small) }
                }
                .padding(6).background(RoundedRectangle(cornerRadius: 7).fill(r.selected ? tokens.selection : .clear))
            }
            ForEach(b.text, id: \.self) { Text($0).font(.system(size: 13, design: b.mono ? .monospaced : .default)).lineSpacing(3) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tokens.separator))
    }

    @ViewBuilder private func lead(_ l: PanelSpec.V2Row.Lead) -> some View {
        switch l {
        case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(.systemGreen)).frame(width: 22, height: 22)
        case .issue: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(.systemRed)).frame(width: 22, height: 22)
        case .off: Image(systemName: "minus").foregroundStyle(tokens.text3).frame(width: 22, height: 22)
        case .dot: Circle().fill(tokens.text3).frame(width: 4, height: 4).frame(width: 22, height: 22)
        case .badge(let t, let c): Text(t).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(c))
        }
    }
}
