import AppKit
import SwiftUI
import OneRoofCore

// LAB-2293 · 7k A run's report (handover 12-7k.png, pages/7k-run-report): the journal report of one run
// (`<journal>/runs/YYYY/MM/<date>_<loop>_<run>.md`, from the ledger's journal_ref) as Read (what it means, what
// happened step by step, goal, findings with their severity, if it had been live, the file) or Source (the markdown as
// is), and Show in Files (the document viewer's preview/source, 2.0.5's run report). A run with no report file says so.

/// The run a report page is for (pushed from 7j).
struct LoopsRunRef: Hashable {
    var id: String
    var loop: String
    var name: String
    var family: String
    var kit: Bool
    var started: Date
    var ref: String
    var result: String

    init(_ r: LoopsV7.FeedRun) {
        id = r.roofdRunId ?? r.id; loop = r.loop; name = r.name; family = r.family; kit = r.engine == .kit
        started = r.started; ref = r.journalRef; result = r.result.rawValue
    }

    /// From a ledger run (self-tests, links).
    init(run r: LoopRun7, row: LoopRow?) {
        id = LoopsV7.roofdRunId(r.id, loop: r.loop) ?? r.id; loop = r.loop; name = row?.name ?? r.loop
        family = row?.family ?? LoopKinds.otherFamily.id; kit = r.engine == .kit; started = r.started; ref = r.journalRef
        result = r.result.rawValue
    }
}

struct LoopRunReport: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    let run: LoopsRunRef
    @State private var loaded: Loaded?
    @State private var source = false
    @State private var confirmRun = false

    /// A report read from disk: its path (nil = no report file), its text and the parse.
    struct Loaded: Equatable {
        var path: String?
        var text: String
        var parsed: LoopReport?
    }

    /// Off the main thread: the journal roots from the kit's config, the file, the parse.
    static func read(_ ref: String) -> Loaded {
        let cfg = AEConfig.find().flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        guard let p = LoopsV7.reportPath(ref, roots: AEConfig.journalRoots(config: cfg)),
              let text = try? String(contentsOfFile: p, encoding: .utf8) else { return Loaded(path: nil, text: "", parsed: nil) }
        return Loaded(path: p, text: text, parsed: LoopReport.parse(text))
    }

    var body: some View {
        Group {
            if let l = loaded {
                if let r = l.parsed, let path = l.path {
                    page(r, text: l.text, path: path)
                } else {
                    none
                }
            } else {
                Text("Reading the report…").ui(13).foregroundStyle(t.text2.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            let ref = run.ref
            DispatchQueue.global(qos: .userInitiated).async {
                let l = Self.read(ref)
                DispatchQueue.main.async { loaded = l }
            }
        }
        .alert("Run \(run.name) again?", isPresented: $confirmRun) {
            Button("Run now") { board.runNowAny(run.loop); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(run.kit ? "The kit runs it once now (`\(KitLoops.command("run", run.loop).dropFirst().joined(separator: " "))`). A loop in trial only writes what it would do."
                         : "One Roof starts a run within 30 s: the check first, then rounds in the loop's own worktree.")
        }
    }

    // MARK: No report

    private var none: some View {
        LoopCard(padding: 18, shadow: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text(run.name + " · run " + run.id).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Text("No report written for this run.").ui(14, .semibold).foregroundStyle(t.text.color)
                Text(run.kit
                     ? "The ledger has no journal report for it" + (run.ref.isEmpty ? "." : " (it points at \(run.ref), which is not on this Mac).")
                     : "One Roof's own loops keep their log in rounds.jsonl (\(run.ref.isEmpty ? run.loop + "/rounds.jsonl" : run.ref)), not as a report file: the check and each round are on the run's steps in Runs.")
                    .ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RoofButton("‹ Runs") { nav.back() }
                    RoofButton("The loop ›") { actions.openLoop(run.loop) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: The report

    private func page(_ r: LoopReport, text: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(run.name + " · " + (r.isTrial ? "trial run" : r.resultWord == "fail" ? "failed run" : "run"))
                    .ui(TypeScale.title + 4, .bold).foregroundStyle(t.text.color).lineLimit(1)
                let mode = LoopLook.tone(r.isTrial ? .trial : r.resultWord == "fail" ? .failing : .fine, theme: t.name)
                chip(r.isTrial ? "shadow · nothing acted" : r.resultWord == "fail" ? "live · failed" : "live · " + r.resultWord, mode)
                chip(LoopsV7.reportFacts(r, family: run.family, started: run.started), LoopLook.tone(.off, theme: t.name))
                Spacer(minLength: 8)
                Segmented(options: [(false, "Read"), (true, "Source")], selection: $source).accessibilityLabel("Read or source")
                RoofButton("Show in Files") { model.openInViewer(path) }
                    .help("Opens the .md in Files (preview and source)")
            }
            if source {
                ScrollView {
                    Text(text).ui(12.5, mono: true).foregroundStyle(t.text.color).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            meaning(r)
                            happened(r)
                            ForEach(Array(r.sections.enumerated()), id: \.offset) { _, s in more(s.title, s.lines) }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 12) {
                            if !r.goal.isEmpty { side("Goal") { Text(r.goal).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true) } }
                            side("Findings · \(r.parsedFindings.count)") { findings(r) }
                            if r.isTrial, !r.ifLive.isEmpty {
                                side("If it had been live") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(r.ifLive.enumerated()), id: \.offset) { _, l in
                                            Text(l).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text("Nothing outside the journal is written.").ui(12).foregroundStyle(t.text2.color)
                                    }
                                }
                            }
                            (Text("File ").bold() + Text((path as NSString).abbreviatingWithTildeInPath))
                                .ui(12.5).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(LoopLook.tone(.running, theme: t.name).fill.color))
                        }
                        .frame(width: 340)
                    }
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
            }
        }
    }

    private func chip(_ s: String, _ p: LoopLook.Pair) -> some View {
        Text(s).ui(12, .semibold).foregroundStyle(p.text.color).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(p.fill.color)).fixedSize()
    }

    private func meaning(_ r: LoopReport) -> some View {
        let m = r.meaning
        let setup = m.headline.contains("not set up")
        let amber = LoopLook.tone(.needsYou, theme: t.name).text
        return VStack(alignment: .leading, spacing: 8) {
            LoopLabel("What it means")
            Text(m.headline).ui(17, .bold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            Text(m.why).ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if setup {
                    RoofButton("Set up " + run.name, .primary) { actions.openLoop(run.loop) }
                        .help("The loop's card says what to set and where (Open config)")
                    RoofButton(r.isTrial ? "Run the trial again" : "Run again") { confirmRun = true }
                } else if r.resultWord == "fail" {
                    RoofButton("Run again", .primary) { confirmRun = true }
                    RoofButton("The loop ›") { actions.openLoop(run.loop) }
                } else {
                    RoofButton("The loop ›") { actions.openLoop(run.loop) }
                }
            }
            .padding(.top, 2)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card, style: .continuous)
                .fill((r.resultWord == "fail" ? t.needsText : setup || r.isTrial ? amber : t.statusDone).color).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func happened(_ r: LoopReport) -> some View {
        LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                LoopLabel("What happened" + (r.totalTime.isEmpty ? "" : " · " + r.totalTime)).padding(.bottom, 6)
                ForEach(Array(r.steps.enumerated()), id: \.offset) { _, s in
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(s.t).ui(12, mono: true).foregroundStyle(t.text2.color).frame(width: 64, alignment: .leading)
                        Text(s.step.prefix(1).uppercased() + s.step.dropFirst()).ui(13, .semibold).foregroundStyle(t.text.color).frame(width: 100, alignment: .leading)
                        Text(s.what).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        if let tag = LoopReport.stepTag(s, trial: r.isTrial) { stepTag(tag) }
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepTag(_ s: String) -> some View {
        let tone: LoopLook.Tone
        switch s {
        case "pass": tone = .fine
        case "fail": tone = .failing
        case "shadow": tone = .trial
        case "started": tone = .off
        default: tone = .off
        }
        let p = LoopLook.tone(tone, theme: t.name)
        return Text(s).ui(11, .semibold).foregroundStyle(p.text.color)
            .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(p.fill.color)).fixedSize()
    }

    private func findings(_ r: LoopReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if r.parsedFindings.isEmpty { Text("None.").ui(12.5).foregroundStyle(t.text2.color) }
            ForEach(Array(r.parsedFindings.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let p = LoopLook.tone(f.severity == "high" ? .failing : f.severity == "medium" ? .needsYou : .off, theme: t.name)
                    Text(f.severity).ui(10.5, .semibold).foregroundStyle(p.text.color)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(p.fill.color)).fixedSize()
                    Text(f.text + (f.outcome.isEmpty ? "" : " → " + f.outcome)).ui(12.5).foregroundStyle(t.text.color)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
    }

    private func side<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        let content = c()
        return LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 6) {
                LoopLabel(label)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func more(_ title: String, _ lines: [String]) -> some View {
        LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 4) {
                LoopLabel(title)
                ForEach(Array(lines.prefix(14).enumerated()), id: \.offset) { _, l in
                    Text(l.hasPrefix("- ") ? String(l.dropFirst(2)) : l).ui(12.5).foregroundStyle(t.text.color)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if lines.count > 14 { Text("\(lines.count - 14) more lines in Source").ui(12).foregroundStyle(t.text2.color) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
