import AppKit
import SwiftUI
import OneRoofCore

// LAB-2294 · 7n States (handover 15-7n.png, 16-7n_empty.png, pages/7n-states): replaces the empty card, the error line,
// Resume all and the setup status (LAB-2100).
//   No loops yet: the 2.0.5 copy, START FROM ONE (one per kind), + New loop, Turn on the kit's loops….
//   Banners (LoopsV7Setup.banners): a write failed (the action and the reason; Try again · Dismiss) · roofd not running
//   (the daemon's own status line and the loops that wait; Start roofd) · everything paused (what is skipped; Resume all)
//   · kit state unknown (`ae loops list` could not be read; Read again).
//   Needs setup: the loops missing a setting or a tool, with the config key; Set up opens the kit config at that key,
//   Install opens the tool's install page.

struct LoopsStateBanners: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard

    var body: some View {
        let bs = LoopsV7Setup.banners(roofdOK: model.runtimeOK, roofdLine: model.runtimeState, loops: board.loops, rows: board.rows,
                                      kitKnown: board.kitKnown, error: board.error)
        ForEach(Array(bs.enumerated()), id: \.offset) { _, b in banner(b) }
    }

    @ViewBuilder private func banner(_ b: LoopsV7Setup.Banner) -> some View {
        switch b {
        case .writeFailed(let action, let reason):
            line(tone: .failing, strong: true, text: "\(action) failed: \(reason)") {
                if board.retry != nil { RoofButton("Try again") { board.tryAgain() } }
                RoofButton("Dismiss", .plain) { board.dismissError() }
            }
            .accessibilityLabel("A write failed: \(action), \(reason)")
        case .roofdDown(let status, let waiting):
            line(tone: .failing, strong: true,
                 text: "One Roof's engine (roofd) is not running: \(status)."
                    + (waiting.isEmpty ? "" : " Waiting for it: " + LoopsV7Setup.names(waiting) + ". The kit's loops run on launchd and are not affected.")) {
                RoofButton("Start roofd") {
                    let m = model
                    DispatchQueue.global(qos: .userInitiated).async { try? m.runtime.ensureRunning() }
                }
                .help("Start the daemon again (One Roof also retries every 5 s on its own)")
            }
        case .paused(let n, let skipped):
            line(tone: .needsYou, strong: false,
                 text: "⏸ Everything is paused: \(n) of One Roof's loops. Skipped until you resume: " + LoopsV7Setup.names(skipped)
                    + ". The kit's loops keep their launchd schedule.") {
                RoofButton("Resume all", .primary) { board.resumeAll() }
            }
        case .kitUnknown:
            line(tone: .needsYou, strong: false,
                 text: "Kit state unknown: `ae loops list` could not be read, so the kit's loops show as unknown, never as off. One Roof's own loops are shown as they are.") {
                RoofButton("Read again") { KitLoopsCache.shared.invalidate(); board.selfTestKitUnknown = false; board.reload() }
            }
        }
    }

    private func line<B: View>(tone: LoopLook.Tone, strong: Bool, text: String, @ViewBuilder buttons: () -> B) -> some View {
        let p = LoopLook.tone(tone, theme: t.name)
        return HStack(spacing: 10) {
            Text(text).ui(12.5, strong ? .semibold : .regular).foregroundStyle(p.text.color)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            buttons()
        }
        .padding(.vertical, 7).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(p.fill.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(p.text.color.opacity(strong ? 0.6 : 0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// The loops that need a setting or a tool before they can run (LP-11), one line each with the key. Folded to one line
/// on the landing until opened (ONEROOF_SELFTEST_LOOPSTATE=setup opens it).
struct LoopsNeedsSetupCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @State private var open = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LOOPSTATE"] == "setup"

    static let installPages = ["osv-scanner": "https://google.github.io/osv-scanner/installation/"]

    var body: some View {
        let items = board.setupItems
        let amber = LoopLook.tone(.needsYou, theme: t.name).text
        VStack(alignment: .leading, spacing: 0) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    Text(LoopsV7Setup.setupTitle(items)).ui(14, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    Text(open ? "▾" : "▸").ui(13).foregroundStyle(t.text2.color)
                }
                .padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LoopsV7Setup.setupTitle(items) + (open ? ", open" : ", folded"))
            if open {
                ForEach(items) { i in
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    HStack(spacing: 12) {
                        Text(i.title).ui(13, .semibold).foregroundStyle(t.text.color).frame(width: 180, alignment: .leading)
                        (Text(i.need + ": ") + Text(i.key ?? i.tool ?? "").font(.system(size: 12, design: .monospaced)))
                            .ui(12.5).foregroundStyle(t.text.color).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let tool = i.tool {
                            if let u = Self.installPages[tool].flatMap(URL.init(string:)) {
                                RoofButton("Install") { NSWorkspace.shared.open(u) }.help("Open \(tool)'s install page")
                            } else {
                                LoopButton("Install", reason: "Not connected: install \(tool) yourself, then the next run uses it") {}
                            }
                        } else {
                            RoofButton("Set up") { openConfig(i) }.help("Open the kit's config at \(i.key ?? "")")
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(i.title): \(i.need), \(i.key ?? i.tool ?? "")")
                }
                Text("Settings live in the kit config, \(((board.aeConfigPath ?? "~/.config/ae/config.yaml") as NSString).abbreviatingWithTildeInPath). One Roof re-reads it when it changes and never edits it.")
                    .ui(12).foregroundStyle(t.text2.color).padding(.top, 6).padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card).fill(amber.color).frame(width: 4) }
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
    }

    private func openConfig(_ i: LoopsV7Setup.SetupItem) {
        guard let cfg = board.aeConfigPath else { model.openInViewer(LoopBuiltIns.defaultRepoPath()); return }
        let line = (try? String(contentsOfFile: cfg, encoding: .utf8)).flatMap { LoopsV7Setup.configLine(i.key ?? "loops.settings.\(i.loop)", in: $0) }
        model.openInViewer(cfg, line: line)
    }
}

/// No loops yet: what a loop is, one way in per kind, + New loop and the kit's loops.
struct LoopsEmptyState: View {
    @Environment(\.theme) private var t
    @ObservedObject var nav: LoopsNav
    var newLoop: () -> Void

    struct Start: Identifiable { let id: String; let title: String; let example: String; let kinds: [String] }
    static let starts = [
        Start(id: "watch", title: "Keep an eye on a number", example: "e.g. memory, spend, a site", kinds: ["sentinel", "prober"]),
        Start(id: "check", title: "Check work against a bar", example: "e.g. docs drift, security", kinds: ["auditor", "judge"]),
        Start(id: "improve", title: "Fix until a check passes", example: "e.g. nightly bugs", kinds: ["fixer", "refresher", "learner"]),
        Start(id: "report", title: "Write something to read", example: "e.g. a morning brief", kinds: ["reporter", "writer", "researcher"]),
    ]

    var body: some View {
        LoopCard(padding: 24, shadow: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No loops yet").ui(TypeScale.title, .bold).foregroundStyle(t.text.color).accessibilityAddTraits(.isHeader)
                Text("A loop repeats work until a check passes, or runs every night. One Roof runs the check, counts the rounds and stops at the limits; an agent does the work in the loop's own worktree, never your checkout. Nothing is pushed or merged.")
                    .ui(13.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                LoopLabel("Start from one").padding(.top, 4)
                HStack(spacing: 10) {
                    ForEach(Self.starts) { s in startCard(s) }
                }
                HStack(spacing: 8) {
                    RoofButton("+ New loop", .primary) { newLoop() }
                    RoofButton("Turn on the kit's loops…") { nav.setRoot(.library) }
                        .help("The Library: every kit loop, off ones with Turn on (\(LoopsV7Setup.trialRuns) trial runs first)")
                }
            }
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private func startCard(_ s: Start) -> some View {
        let k = LoopLook.kind(s.id, theme: t.name)
        return Button { start(s) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(LoopKinds.family(s.id)?.title ?? s.id).ui(11.5, .semibold).foregroundStyle(k.text.color)
                Text(s.title).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(s.example).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separatorStrong.color, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .accessibilityLabel("\(LoopKinds.family(s.id)?.title ?? s.id): \(s.title), \(s.example)")
    }

    /// New loop from the kit's first example of that kind (fix until green for Improve), with the kind set.
    private func start(_ s: Start) {
        let tpl = s.id == "improve" ? LoopTemplates.fixUntilGreen : LoopTemplates.builtInTemplates().first { s.kinds.contains($0.kind ?? "") }
        var d = LoopDraft.new(template: tpl)
        d.loop.kind = tpl?.kind ?? s.kinds.first
        nav.newLoop(d)
    }
}
