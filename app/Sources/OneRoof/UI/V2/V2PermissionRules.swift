import SwiftUI
import OneRoofCore

/// LAB-2110: the always-allow rules One Roof notes, in Settings › Permissions (moved from the Action log's Rules tab):
/// search, Stop noting this rule, Undo for 5 s.
struct PermissionRulesSection: View {
    let model: AppModel
    @State private var rules: [DecisionRule] = []
    @State private var search = ""
    @State private var stopped: DecisionRule?

    var body: some View {
        Section("Always-allow rules One Roof notes") {
            Text(ActionLog.rulesExplainer).font(.caption).foregroundStyle(.secondary)
            TextField("Search rules", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300).accessibilityLabel("Search rules")
            let n = search.trimmingCharacters(in: .whitespaces).lowercased()
            let shown = rules.filter { n.isEmpty || $0.pattern.lowercased().contains(n) || $0.repo.lowercased().contains(n) }
            if shown.isEmpty { Text(rules.isEmpty ? ActionLog.emptyRules : "No rule matches.").foregroundStyle(.secondary) }
            ForEach(shown, id: \.id) { r in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.pattern).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).lineLimit(1)
                        Text(Workspace.repoLabel(for: r.repo) + " · added " + HistoryFormat.stamp(r.createdAt)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(ActionLog.stopRule) { stop(r) }
                        .help("Removes One Roof's note only; the agent keeps its own always-allow setting")
                        .accessibilityLabel(ActionLog.stopAccessibility(r))
                }
            }
            if let r = stopped {
                HStack {
                    Text(ActionLog.stopped(r)).font(.caption)
                    Button("Undo") { model.restoreRule(r); stopped = nil; reload() }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let store = model.store
        DispatchQueue.global(qos: .userInitiated).async {
            let rs = store?.decisionRulesNewestFirst() ?? []
            DispatchQueue.main.async { rules = rs }
        }
    }

    private func stop(_ r: DecisionRule) {
        model.stopNoting(r)
        rules.removeAll { $0.id == r.id }
        stopped = r
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if stopped?.id == r.id { stopped = nil } }
    }
}
