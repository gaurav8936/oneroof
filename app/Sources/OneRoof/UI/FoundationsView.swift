import AppKit
import SwiftUI
import OneRoofCore

/// Window › Foundations (⌘⇧F): the startup check, and read-only views of the skills, hooks, rules and memory that
/// every agent shares. Everything is read from the agentic-engineering folder and _common; nothing is copied (owner D7).
struct FoundationsView: View {
    @ObservedObject var model: AppModel
    @State var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CheckTab(model: model).tabItem { Label("Check", systemImage: "checkmark.shield") }.tag(0)
            SkillsTab(model: model).tabItem { Label("Skills", systemImage: "wand.and.stars") }.tag(1)
            HooksTab(model: model).tabItem { Label("Hooks & rules", systemImage: "link") }.tag(2)
            MemoryTab(model: model).tabItem { Label("Memory", systemImage: "brain") }.tag(3)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 540)
    }
}

private func levelColor(_ l: CheckLevel) -> Color {
    switch l {
    case .ok: return Pastel.named("mint")!.lightInk.color
    case .warn: return Pastel.named("peach")!.lightInk.color
    case .fail: return Pastel.named("coral")!.lightInk.color
    }
}

private func levelFill(_ l: CheckLevel) -> Color {
    Pastel.named(l == .ok ? "mint" : l == .warn ? "peach" : "coral")!.lightFill.color
}

private func levelSymbol(_ l: CheckLevel) -> String {
    l == .ok ? "checkmark.circle.fill" : l == .warn ? "exclamationmark.circle.fill" : "xmark.octagon.fill"
}

struct CheckTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let l = model.foundationsLevel {
                    Label(l == .ok ? "All foundations in place" : l == .warn ? "Works, with warnings" : "Problems to fix before agents start",
                          systemImage: levelSymbol(l))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(levelColor(l))
                } else {
                    Text("Not checked yet").font(.system(size: 15, weight: .bold))
                }
                Spacer()
                if let at = model.foundationsCheckedAt {
                    Text("checked \(at.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                Button { model.runFoundations() } label: {
                    if model.checkingFoundations { ProgressView().controlSize(.small) } else { Label("Check again", systemImage: "arrow.clockwise") }
                }
            }
            Text("One Roof reads these and runs the workspace's own check scripts. It never copies skills, hooks or rules.")
                .font(.caption).foregroundStyle(.secondary)
            if model.settings.ui2 {   // B2, NEW-21: every fix in one terminal, one after another
                // Red rows only (warnings are optional add-ons), and not a fix that starts a long-running process
                // (the roofd daemon): with "; " each fix runs after the previous one ends, failures or not.
                let fixes = model.foundations.filter { $0.level == .fail }.compactMap { r in r.fix.map { (r.title, $0) } }
                    .filter { !$0.1.hasSuffix(" daemon") }
                if fixes.count > 1 {
                    HStack {
                        Spacer()
                        Button("Fix all \(fixes.count)") {
                            model.runInTerminal(fixes.map { "echo '▶ \($0.0.replacingOccurrences(of: "'", with: ""))'; \($0.1)" }.joined(separator: "; "), title: "Fix all foundations")
                        }
                        .help("Runs each fix in one One Roof terminal, in order: " + fixes.map(\.1).joined(separator: " ; "))
                    }
                }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.foundations) { r in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: levelSymbol(r.level)).foregroundStyle(levelColor(r.level)).font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.system(size: 13, weight: .semibold))
                                Text(r.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                if r.id == "localmodel" {
                                    // LAB-675: the model file is fixed here, not by a terminal command.
                                    ModelDownloadRow(download: model.modelDownload, offer: LocalModel.offerDownload(modelPath: LocalModel.modelPath))
                                }
                            }
                            Spacer()
                            if let fix = r.fix {
                                Button("Fix") { model.runInTerminal(fix, title: "Fix: \(r.title)") }
                                    .help("Runs in a One Roof terminal: \(fix)")
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(r.level == .ok ? Color.primary.opacity(0.04) : levelFill(r.level).opacity(0.6)))
                    }
                }
            }
        }
    }
}

struct SkillsTab: View {
    @ObservedObject var model: AppModel
    @State private var skills: [Foundations.SkillInfo] = []
    @State private var query = ""
    @State private var loading = true

    var filtered: [Foundations.SkillInfo] {
        let q = query.lowercased()
        return q.isEmpty ? skills : skills.filter { ($0.name + " " + $0.track + " " + $0.description).lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search \(skills.count) skills", text: $query).textFieldStyle(.roundedBorder)
                Text("from \(model.settings.agenticEngineering.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))/skills")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            List(filtered) { s in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.name).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            Text(s.track).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        }
                        Text(s.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(["Claude", "Codex", "Kimi", "Gemini/agy"], id: \.self) { h in
                            Text(h == "Gemini/agy" ? "GM" : String(h.prefix(2)).uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(s.linkedIn.contains(h) ? Pastel.named("mint")!.lightInk.color : .secondary.opacity(0.5))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(s.linkedIn.contains(h) ? Pastel.named("mint")!.lightFill.color : Color.primary.opacity(0.05)))
                                .help(s.linkedIn.contains(h) ? "Linked into \(h)" : "Not linked into \(h)")
                        }
                    }
                    Button { insert(s) } label: { Image(systemName: "text.insert") }
                        .buttonStyle(.borderless)
                        .disabled(model.selected?.liveAgent == nil)
                        .help("Type /\(s.name) into the selected session (not sent)")
                    Button { model.openInViewer(s.path + "/SKILL.md") } label: { Image(systemName: "doc.text") }
                        .buttonStyle(.borderless).help("Open SKILL.md")
                    Button {
                        model.learnTarget = s.path + "/" + (s.path as NSString).lastPathComponent + ".html"
                        model.learnMode = true
                    } label: { Image(systemName: "graduationcap") }
                        .buttonStyle(.borderless).help("Learn: open this skill's narrated page in One Roof")
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let p = FoundationPaths(common: model.settings.sharedFolder, agenticEngineering: model.settings.agenticEngineering.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Foundations.skills(p)
            DispatchQueue.main.async { skills = list; loading = false }
        }
    }

    private func insert(_ s: Foundations.SkillInfo) {
        guard let pane = model.selected?.paneId else { return }
        let r = model.runtime
        DispatchQueue.global().async { try? r.type(pane: pane, text: "/\(s.name) ") }
    }
}

struct HooksTab: View {
    @ObservedObject var model: AppModel
    @State private var hooks: [Foundations.Hook] = []

    var body: some View {
        let common = model.settings.sharedFolder
        VStack(alignment: .leading, spacing: 10) {
            Text("Rules every agent reads").font(.system(size: 13, weight: .bold))
            HStack(spacing: 12) {
                docLink("READ-FIRST", common + "/docs/READ-FIRST.md")
                docLink("Rulebook (AGENTS.md)", common + "/AGENTS.md")
                docLink("Workspace CLAUDE.md", Workspace.projectsRoot + "/CLAUDE.md")
                docLink("Never-override rules", common + "/docs/standards/20260911_01_never-override-rules.md")
            }
            Divider()
            Text("Claude hooks (~/.claude/settings.json, shared by both Claude homes)").font(.system(size: 13, weight: .bold))
            List(hooks) { h in
                HStack(alignment: .top) {
                    Text(h.event).font(.system(size: 11, weight: .bold)).frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.command).font(.system(size: 11, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                        if let m = h.matcher, !m.isEmpty { Text("matcher: \(m)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: h.scriptExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(h.scriptExists ? levelColor(.ok) : levelColor(.warn))
                        .help(h.scriptExists ? "script present" : "script missing: \(h.script)")
                }
            }
            Text("Codex, Kimi and Antigravity have no hooks; the launch guard reaches them through PATH stand-ins and the doors.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { hooks = Foundations.hooks() }
    }

    private func docLink(_ title: String, _ path: String) -> some View {
        Button { model.openInViewer(path) } label: { Label(title, systemImage: "doc.text") }
            .buttonStyle(.link)
            .disabled(!FileManager.default.fileExists(atPath: path))
    }
}

struct MemoryTab: View {
    @ObservedObject var model: AppModel
    @State private var handoffs: [Foundations.DocFile] = []
    @State private var gotchas: [Foundations.DocFile] = []
    @State private var memory = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latest handoff per project").font(.system(size: 13, weight: .bold))
                List(handoffs) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.workstream ?? "—").font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(f.title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Resume") { resume(f) }.controlSize(.small)
                            .help("Plan a Claude session that reads this handoff and continues from its next action")
                        Button { model.openInViewer(f.path) } label: { Image(systemName: "doc.text") }
                            .buttonStyle(.borderless)
                    }
                }
                Text("Recent gotchas").font(.system(size: 13, weight: .bold))
                List(gotchas) { f in
                    Button { model.openInViewer(f.path) } label: {
                        Text(f.title).font(.system(size: 11)).lineLimit(1)
                    }.buttonStyle(.plain)
                }
                .frame(maxHeight: 160)
            }
            .frame(minWidth: 380)
            VStack(alignment: .leading, spacing: 6) {
                Text("MEMORY.md (the one Claude memory)").font(.system(size: 13, weight: .bold))
                ScrollView { Text(memory).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .frame(minWidth: 300)
        }
        .onAppear(perform: load)
    }

    private func load() {
        let p = FoundationPaths(common: model.settings.sharedFolder, agenticEngineering: model.settings.agenticEngineering.path)
        handoffs = Foundations.handoffs(p)
        gotchas = Foundations.gotchas(p)
        memory = (try? String(contentsOfFile: p.memoryFolder + "/MEMORY.md", encoding: .utf8)) ?? "MEMORY.md not found"
    }

    private func resume(_ f: Foundations.DocFile) {
        let s = Session(name: "Resume " + (f.workstream ?? f.title), agent: .claude,
                        account: model.settings.defaults(for: .claude).account, repoPath: Workspace.projectsRoot,
                        workstream: f.workstream,
                        objective: "Continue from the handoff \(f.title)",
                        openingMessage: "Read \(f.path) and continue from its NEXT ACTION.",
                        lifecycle: .next)
        model.createPlanned(s, launchNow: false)
        model.selectedId = s.id
    }
}

final class FoundationsWindowController: NSWindowController {
    convenience init(model: AppModel, tab: Int = 0) {
        let host = NSHostingController(rootView: FoundationsView(model: model, tab: tab))
        let w = NSWindow(contentViewController: host)
        w.title = "One Roof Foundations"
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 860, height: 600))
        self.init(window: w)
        w.center()
    }
}
