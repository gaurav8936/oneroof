import AppKit
import SwiftUI
import OneRoofCore

// LAB-2290 · 7l A round asks permission (handover 13-7l.png, pages/7l-question): the Inbox's card for a loop whose round
// asks something (LoopInbox's `.asks` item). Tag LOOP · QUESTION, age, Open loop › (→ 7c); the title in plain words; the
// command in a code box (only when the engine read one off the round's prompt: never invented); where (worktree, branch)
// and the agent's reason; Allow once · Always for this loop · Deny, and say why… · Open the session ↗; three notes.
// Allow once and Deny answer exactly as Decisions does for any session (AppModel.answer → the engine presses the agent's
// own key, only when you press it: One Roof never answers by itself). With no prompt read, they are off and say so, and
// Open the session ↗ is how you answer, in the round's terminal. Always for this loop writes one exact allow rule into
// the loop worktree's `.claude/settings.local.json` (Claude rounds only), then allows once; otherwise it is off with the
// reason. The same answers sit in 7d's top row (compact).

extension AppModel {
    /// The open permission prompt the engine read for a loop round's session (LAB-1933 keeps it out of Decisions and the
    /// Inbox's session blocks; the loop item carries it). Self-test asks included.
    func loopRoundPrompt(_ sessionId: String?) -> Decision? {
        guard let sid = sessionId else { return nil }
        return (selfTestDecisions + decisions).last { $0.sessionId == sid && $0.isOpen && !$0.isFinished }
    }
}

/// The answers (Allow once · Always for this loop · Deny, and say why… · Open the session ↗), full or compact (7d).
struct LoopQuestionAnswers: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var win: WindowState?
    let question: LoopQuestion
    var compact = false
    @State private var denying = false
    @State private var reason = ""
    @State private var confirmAlways = false
    @State private var result: String?

    private var prompt: Decision? { model.loopRoundPrompt(question.sessionId) }
    private var reachable: Bool { prompt.map { model.canReach($0) } ?? false }
    private var noPromptReason: String? {
        guard let p = prompt else { return "No prompt was read from the round: answer it in its terminal (Open the session ↗)." }
        return model.canReach(p) ? nil : "Couldn't reach the round's terminal from here: open the session and answer there."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                Text("The round is on hold until you answer." + (question.command.map { " It wants to run `\($0)`." } ?? ""))
                    .ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                LoopButton("Allow once", .primary, reason: noPromptReason) { answer(.allowOnce) }
                    .help("Yes, this time only: One Roof presses the agent's own yes key for you")
                let alwaysOff = LoopAllowRule.unavailable(agent: question.agent, command: question.command, worktree: question.worktree)
                    ?? noPromptReason
                LoopButton(compact ? "Always for this loop" : "Always allow for this loop", reason: alwaysOff) { confirmAlways = true }
                    .help(alwaysOff ?? "Adds `\(LoopAllowRule.rule(agent: question.agent, command: question.command) ?? "")` to this loop's allow list, then allows once")
                LoopButton(compact ? "Deny…" : "Deny, and say why…", reason: noPromptReason) { denying.toggle() }
                if !compact {
                    let it = question.sessionId.flatMap { model.item($0) }
                    LoopButton("Open the session ↗", reason: it == nil ? "The round's session is not running" : nil) { if let it { model.reveal(it) } }
                }
            }
            if denying {
                HStack(spacing: 8) {
                    TextField("Why (goes back to the round)", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                    RoofButton("Deny", .danger) { answer(reason.trimmingCharacters(in: .whitespaces).isEmpty ? .deny : .reply, reply: reason); denying = false }
                }
            }
            if let result {
                Text(result).ui(12.5).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Always allow this command for \(question.loopTitle)?", isPresented: $confirmAlways) {
            Button("Add the rule and allow once") { always() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Writes `\(LoopAllowRule.rule(agent: question.agent, command: question.command) ?? "")` to permissions.allow in \((LoopAllowRule.settingsPath(worktree: question.worktree) as NSString).abbreviatingWithTildeInPath) (this loop's worktree only, never your checkout), then answers this prompt Allow once. Its next rounds run that exact command without asking.")
        }
    }

    private func answer(_ a: Answer, reply: String? = nil) {
        guard let d = prompt, reachable else { return }
        model.answer(d, a, reply: reply)
        result = a == .allowOnce ? "Allowed once: the round goes on." : "Denied" + (reply.map { $0.isEmpty ? "." : ": \($0)" } ?? ".") + " The reason goes back to the round."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
    }

    private func always() {
        guard let rule = LoopAllowRule.rule(agent: question.agent, command: question.command), let d = prompt else { return }
        let wt = question.worktree
        DispatchQueue.global(qos: .userInitiated).async {
            let err: String?
            do { try LoopAllowRule.write(rule: rule, worktree: wt); err = nil } catch { err = "\(error)" }
            DispatchQueue.main.async {
                if let err { result = "The rule was not written: \(err). Nothing was answered."; return }
                model.answer(d, .allowOnce)
                result = "Added \(rule) to this loop's allow list and allowed once."
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
            }
        }
    }
}

/// The full card (the Inbox with the loop question selected).
struct LoopQuestionCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var win: WindowState?
    let item: LoopInbox.Item
    @State private var loop: Loop?

    var body: some View {
        let q = LoopQuestion.make(item: item, loop: loop, prompt: model.loopRoundPrompt(item.sessionId))
        let amber = LoopLook.tone(.needsYou, theme: t.name)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("LOOP · QUESTION").ui(11, .semibold).tracking(0.66).foregroundStyle(amber.text.color)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(amber.fill.color))
                Text(LoopsV7.age(q.askedAt) + " ago").ui(12.5).foregroundStyle(t.text2.color)
                Spacer()
                Button { model.openLoop(item.loopId, in: win) } label: {
                    Text("Open loop ›").ui(13, .semibold).foregroundStyle(t.accentText.color)
                }
                .buttonStyle(.plain).help("The loop's page (its state, runs and what you can do)")
            }
            Text(q.title).ui(20, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let c = q.command {
                Text(c).ui(13.5, .medium, mono: true).foregroundStyle(LoopQuestionCard.codeText(t.name).color).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(LoopQuestionCard.codeFill(t.name).color))
                    .accessibilityLabel("Command: " + c)
            } else {
                Text("No command was read from the round's prompt. Open the session to see what it asks.")
                    .ui(13).foregroundStyle(t.text2.color)
            }
            whereLine(q)
            LoopQuestionAnswers(model: model, win: win, question: q)
            HStack(alignment: .top, spacing: 10) {
                note("While it waits", "The round is on hold. The loop shows \"Needs you\" and starts nothing else.")
                note("Never asked", "Push, merge and deploy are refused outright by the round's rules, never offered here.")
                note("Not asked", "Commands the agent already allows itself don't come here.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(amber.text.color, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loop question: " + q.title)
        .task(id: item.loopId) {
            let id = item.loopId
            let l = await Task.detached { LoopInboxState.store().load(id) }.value
            loop = l
        }
    }

    private func whereLine(_ q: LoopQuestion) -> some View {
        var parts: [String] = []
        if !q.worktree.isEmpty {
            parts.append("In its worktree \((q.worktree as NSString).abbreviatingWithTildeInPath)" + (q.branch.isEmpty ? "" : ", on branch \(q.branch)") + ".")
        }
        parts.append(q.reason.map { "Its reason: \u{201C}\($0)\u{201D}" } ?? "The agent gave no reason.")
        return Text(parts.joined(separator: " ")).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).ui(12.5, .semibold).foregroundStyle(t.text.color)
            Text(text).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.control.color))
    }

    /// The code box: dark in a light look (as the shot draws it); a step lighter than the card in a dark look (the
    /// Inbox draws its blocks dark, so Midnight on Midnight would not show as a box).
    static func codeFill(_ n: ThemeName) -> RGB { n.isDark ? n.tokens.control.over(n.tokens.surface) : ThemeName.midnight.tokens.surface }
    static func codeText(_ n: ThemeName) -> RGB { n.isDark ? n.tokens.text : ThemeName.midnight.tokens.text }
}
