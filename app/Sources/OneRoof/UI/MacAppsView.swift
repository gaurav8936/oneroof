import AppKit
import SwiftUI
import OneRoofCore

/// LAB-544: Resources › This Mac, by app. Every app's memory and CPU with all its processes (helpers and the XPC
/// services it started count to it, as in Activity Monitor), heaviest first. An app opens to its processes, where a
/// Chrome or Electron helper says what it is (tab or site, extension, GPU …). Apps can be quit and single processes
/// ended from here, each after a confirmation; One Roof's own leftovers (a local model a force-quit left running, a
/// roofd this One Roof does not use) are called out at the top with a Stop button.
struct MacAppsCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var res: ResourceMonitor
    @State private var open: Set<String> = []
    @State private var showAll = false
    @State private var showAllProcs: Set<String> = []
    @State private var pending: Pending?
    @State private var message: String?

    static let firstApps = 12
    static let firstProcs = 25

    /// An action waiting for its confirmation.
    enum Pending: Identifiable {
        case quit(MacAppGroup, force: Bool)
        case end(MacProc, force: Bool)
        var id: String {
            switch self {
            case .quit(let g, let f): return "quit:\(g.id):\(f)"
            case .end(let p, let f): return "end:\(p.pid):\(f)"
            }
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                if let b = res.mac { content(b) } else {
                    header(detail: "reading…")
                    Hairline()
                    Text("Reading every app's memory and CPU…").ui(12.5).foregroundStyle(t.text2.color).padding(14)
                }
            }
        }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { p in
            Button(confirmLabel(p), role: .destructive) { run(p) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { p in Text(dialogMessage(p)) }
    }

    @ViewBuilder private func content(_ b: MacBreakdown) -> some View {
        let groups = showAll ? b.groups : Array(b.groups.prefix(Self.firstApps))
        header(detail: detail(b))
        Hairline()
        if let message {
            HStack(spacing: 8) {
                Text(message).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("✕") { self.message = nil }.buttonStyle(.plain).ui(11).foregroundStyle(t.text2.color).accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Hairline()
        }
        ForEach(b.leftovers) { p in
            leftover(p)
            Hairline()
        }
        LazyVStack(spacing: 0) {
            ForEach(groups) { g in
                appRow(g, b)
                if open.contains(g.id) { processes(g) }
                Hairline().padding(.leading, 14)
            }
        }
        HStack(spacing: 10) {
            if b.groups.count > Self.firstApps {
                Button(showAll ? "Show the top \(Self.firstApps)" : "Show all \(b.groups.count) apps") { showAll.toggle() }
                    .buttonStyle(.link).ui(12)
            }
            Spacer()
            Text(footnote(b)).ui(11).foregroundStyle(t.text3.color).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func header(detail: String) -> some View {
        HStack(spacing: 8) {
            Text("This Mac, by app").ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
            Text(detail).ui(12).foregroundStyle(t.text3.color).lineLimit(1).truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 36)
        .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ b: MacBreakdown) -> String {
        var s = "\(b.groups.count) apps · \(b.processCount) processes"
        if let m = b.mac { s = "\(ResourceFormat.bytes(m.used)) of \(ResourceFormat.bytes(m.total)) in use · swap \(ResourceFormat.bytes(m.swapUsed)) · " + s }
        return s
    }

    private func footnote(_ b: MacBreakdown) -> String {
        var s = "\(b.unreadable) system and other users' processes are not counted (macOS shows them to administrators only)"
        if b.uncounted > 0 { s += " · \(ResourceFormat.bytes(b.uncounted)) in use outside the apps listed" }
        return s
    }

    // MARK: Leftovers

    private func leftover(_ p: MacProc) -> some View {
        HStack(spacing: 10) {
            Text("●").ui(11).foregroundStyle(t.now.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.kind ?? p.name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text("One Roof did not start this one and nothing uses it; it keeps its memory until stopped. One Roof starts a fresh one when it needs it.")
                    .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(ResourceFormat.bytes(p.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(t.now.color)
            Button("Stop") { pending = .end(p, force: false) }.controlSize(.small)
                .accessibilityLabel("Stop \(p.kind ?? p.name), \(ResourceFormat.bytes(p.footprint))")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(t.now.color.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    // MARK: Apps

    private func appRow(_ g: MacAppGroup, _ b: MacBreakdown) -> some View {
        let isOpen = open.contains(g.id)
        let share = Double(g.footprint) / Double(max(b.mac?.used ?? b.counted, 1))
        return HStack(spacing: 10) {
            Button {
                if isOpen { open.remove(g.id) } else { open.insert(g.id) }
            } label: {
                HStack(spacing: 10) {
                    Text(isOpen ? "▾" : "▸").ui(10).foregroundStyle(t.text3.color).frame(width: 10)
                    AppIcon(bundlePath: g.bundlePath).frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Text(subtitle(g)).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Meter(fraction: share, colour: t.accent).frame(width: 70)
                    Text(ResourceFormat.cpu(g.cpu)).ui(12.5, mono: true).foregroundStyle(t.text2.color).frame(width: 58, alignment: .trailing)
                    Text(ResourceFormat.bytes(g.footprint)).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
                        .frame(width: 72, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(g.name), \(g.procs.count) processes, memory \(ResourceFormat.bytes(g.footprint)), CPU \(ResourceFormat.cpu(g.cpu))")
            .accessibilityHint(isOpen ? "Hides its processes" : "Shows its processes")
            Group {
                if g.quittable {
                    Menu {
                        Button("Quit \(g.name)…") { pending = .quit(g, force: false) }
                        Button("Force quit \(g.name)…") { pending = .quit(g, force: true) }
                    } label: { Text("Quit").ui(11.5, .medium).foregroundStyle(t.text.color) }
                    primaryAction: { pending = .quit(g, force: false) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Quit \(g.name) (it may ask to save first). The arrow offers Force quit.")
                    .accessibilityLabel("Quit \(g.name)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .hoverHighlight()
    }

    private func subtitle(_ g: MacAppGroup) -> String {
        let n = g.procs.count
        var s = "\(n) process\(n == 1 ? "" : "es")"
        let tabs = g.procs.filter { $0.kind == "Tab or site" }.count
        if tabs > 0 { s += " · \(tabs) tabs or sites" }
        if g.isOneRoof { s += " · app, roofd, sessions and the local model" }
        return s
    }

    // MARK: Processes

    @ViewBuilder private func processes(_ g: MacAppGroup) -> some View {
        let all = showAllProcs.contains(g.id)
        let procs = all ? g.procs : Array(g.procs.prefix(Self.firstProcs))
        VStack(alignment: .leading, spacing: 0) {
            let kinds = kindSummary(g)
            if !kinds.isEmpty {
                Text(kinds).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            if g.procs.contains(where: { $0.kind == "Tab or site" }) {
                HStack(spacing: 6) {
                    Text("Tab names: \(g.name) lists each tab with its memory in its own Task Manager (⇧Esc in \(g.name), or Window › Task Manager), and can end a tab there. Ending a \"Tab or site\" here shows that tab as crashed until reloaded.")
                        .ui(11.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                    if let pid = g.mainPid {
                        Button("Show \(g.name)") { NSRunningApplication(processIdentifier: pid)?.activate() }
                            .buttonStyle(.link).ui(11.5).fixedSize()
                    }
                }
                .padding(.bottom, 6)
            }
            ForEach(procs) { p in procRow(p) }
            if g.procs.count > Self.firstProcs {
                Button(all ? "Show the top \(Self.firstProcs)" : "Show all \(g.procs.count) processes") {
                    if all { showAllProcs.remove(g.id) } else { showAllProcs.insert(g.id) }
                }
                .buttonStyle(.link).ui(11.5).padding(.top, 4)
            }
        }
        .padding(.leading, 54).padding(.trailing, 14).padding(.vertical, 8)
        .background(t.surface2.color.opacity(0.5))
    }

    /// "67 Tab or site 10 GB · GPU 690 MB · …", heaviest first, for apps whose processes have kinds.
    private func kindSummary(_ g: MacAppGroup) -> String {
        var by: [String: (n: Int, bytes: UInt64)] = [:]
        for p in g.procs { if let k = p.kind { by[k, default: (0, 0)].n += 1; by[k]!.bytes += p.footprint } }
        guard !by.isEmpty else { return "" }
        return by.sorted { $0.value.bytes > $1.value.bytes }.map { k, v in
            (v.n > 1 ? "\(v.n) × " : "") + "\(k) \(ResourceFormat.bytes(v.bytes))"
        }.joined(separator: " · ")
    }

    private func procRow(_ p: MacProc) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(p.kind ?? p.name).ui(12, p.kind == nil ? .regular : .medium).foregroundStyle(t.text.color).lineLimit(1)
                if p.kind != nil { Text(p.name).ui(10.5, mono: true).foregroundStyle(t.text3.color).lineLimit(1).truncationMode(.middle) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(p.path)
            Text("\(p.pid)").ui(11, mono: true).foregroundStyle(t.text3.color).frame(width: 56, alignment: .trailing)
            Text(ResourceFormat.cpu(p.cpu)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 50, alignment: .trailing)
            Text(ResourceFormat.bytes(p.footprint)).ui(11.5, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 66, alignment: .trailing)
            Group {
                if p.endable {
                    Menu {
                        Button("End…") { pending = .end(p, force: false) }
                        Button("Force end…") { pending = .end(p, force: true) }
                    } label: { Text("End").ui(11, .medium).foregroundStyle(t.text2.color) }
                    primaryAction: { pending = .end(p, force: false) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("End this process (it may tidy up first). The arrow offers Force end.")
                    .accessibilityLabel("End \(p.kind ?? p.name), process \(p.pid)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(p.kind ?? p.name), process \(p.pid), CPU \(ResourceFormat.cpu(p.cpu)), memory \(ResourceFormat.bytes(p.footprint))")
    }

    // MARK: Confirm and run

    private var dialogTitle: String {
        switch pending {
        case .quit(let g, let f)?: return (f ? "Force quit " : "Quit ") + g.name + "?"
        case .end(let p, let f)?: return (f ? "Force end " : "End ") + (p.kind ?? p.name) + "?"
        case nil: return ""
        }
    }

    private func confirmLabel(_ p: Pending) -> String {
        switch p {
        case .quit(_, let f): return f ? "Force quit" : "Quit"
        case .end(_, let f): return f ? "Force end" : "End"
        }
    }

    private func dialogMessage(_ p: Pending) -> String {
        switch p {
        case .quit(let g, let f):
            return "Frees about \(ResourceFormat.bytes(g.footprint)). " + (f ? "Force quit closes it at once: anything unsaved is lost." : "\(g.name) may ask to save first.")
        case .end(let p, let f):
            var s = "\(p.name), pid \(p.pid), uses \(ResourceFormat.bytes(p.footprint)). "
            if p.kind == "Tab or site" { s += "Its tab or site stops and shows as crashed until reloaded. " }
            if p.kind?.hasPrefix("Local model") == true { s += "One Roof starts a fresh local model the next time it needs one. " }
            s += f ? "Force end stops it at once." : "It gets the chance to tidy up first."
            return s
        }
    }

    private func run(_ p: Pending) {
        pending = nil
        switch p {
        case .quit(let g, let f): message = res.quit(g, force: f)
        case .end(let proc, let f): message = res.end(proc, force: f)
        }
    }
}

/// An app's Finder icon, cached per bundle (a plain square for processes outside any app).
struct AppIcon: View {
    @Environment(\.theme) private var t
    let bundlePath: String?
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let p = bundlePath, let img = Self.icon(p) {
            Image(nsImage: img).resizable().interpolation(.high).accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.control.color).accessibilityHidden(true)
        }
    }

    private static func icon(_ path: String) -> NSImage? {
        if let i = cache[path] { return i }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache[path] = i
        return i
    }
}
