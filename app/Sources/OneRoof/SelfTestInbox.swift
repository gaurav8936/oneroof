import Foundation
import OneRoofCore

/// LAB-2042 · ONEROOF_SELFTEST_INBOX=<n> (with ONEROOF_SELFTEST_DEMO=1): the demo sessions ask you things, so the
/// Inbox has blocks to capture. n = how many blocks (0…7, in this order): a permission prompt with 4 options, a menu,
/// a question, a finished turn, a plan waiting for approval, a loop that stopped, a permission with no options read
/// (Allow once · Always allow this · Deny). n ≥ 6 also adds one answered ask (the Decided list). The asks have no pane:
/// answering one records the answer in place (AppModel.answerSelfTest), so the fold after an answer can be captured.
/// ONEROOF_SELFTEST_INBOXPICK=<i> focuses the i-th block (as `needspick i` does); INBOXDECIDED=1 opens Decided;
/// INBOXIMAGE=<png> attaches that image to the focused block's reply box (as `inboxattach <png>` does).
/// INBOXREPLY=<text> types into the focused block's box and sends it (at 2.6 s); INBOXPRESS=<n> presses its option n
/// (at INBOXPRESSAT seconds, default 6.2, so the fold shows in the capture); INBOXOFFLINE=1 makes the seeded sessions
/// unreachable (the "Couldn't reach" state).
enum SelfTestInbox {
    static var offline: Bool { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_INBOXOFFLINE"] == "1" }
    static func seed(_ m: AppModel, count n: Int) {
        func sid(_ name: String) -> String? { m.items.first { $0.session.name == name }?.id }
        let now = Date()
        var out: [Decision] = []
        if n >= 1, let s = sid("Flaky login test") {
            out.append(Decision(sessionId: s, agent: .claude, kind: .runCommand, command: "swift test --filter LoginTests --repeat 20",
                                why: "The login test failed once in CI; running it 20 times shows whether the retry fix holds.",
                                touches: "Runs the tests in acme/web; writes only .build/.", risk: .low,
                                ifNo: "Claude stops and asks you what to do instead.", where_: "Step 3 of 5 · fix the flaky login test",
                                history: DecisionHistory(similarAllowed: 3, ruleSuggestion: "Always allow swift test in acme/web"),
                                pattern: "swift test", repo: "acme/web", askedAt: now.addingTimeInterval(-4 * 60),
                                choices: [DecisionChoice(label: "Yes", key: "1"),
                                          DecisionChoice(label: "Yes, allow all edits during this session", key: "2"),
                                          DecisionChoice(label: "Yes, and don't ask again for swift test commands in acme/web", key: "3"),
                                          DecisionChoice(label: "No, and tell Claude what to do differently", key: "4", freeText: true)],
                                screen: [" Bash command", "", "   swift test --filter LoginTests --repeat 20",
                                         "   Run the login tests 20 times to check the retry fix", "",
                                         " Do you want to proceed?", " ❯ 1. Yes", "   2. Yes, allow all edits during this session",
                                         "   3. Yes, and don't ask again for swift test commands in acme/web",
                                         "   4. No, and tell Claude what to do differently (esc)"]))
        }
        if n >= 2, let s = sid("Help map as a tree") {
            out.append(Decision(sessionId: s, agent: .codex, kind: .other, why: DecisionBuilder.noWhy, whyMissing: true,
                                touches: "A question: nothing runs until you pick an answer or type your own.", risk: .low,
                                ifNo: "The agent keeps waiting; it does nothing until you answer.",
                                pattern: "ask:Which order should the help map use?", repo: "docs-site", askedAt: now.addingTimeInterval(-9 * 60),
                                choices: [DecisionChoice(label: "Folders first, then pages", key: "1"),
                                          DecisionChoice(label: "A to Z, folders and pages mixed", key: "2"),
                                          DecisionChoice(label: "Type something.", key: "3", freeText: true)],
                                screen: ["  Which order should the help map use?", "", "  › 1. Folders first, then pages",
                                         "    2. A to Z, folders and pages mixed", "    3. Type something."]))
        }
        if n >= 3, let s = sid("Nightly usage export") {
            let q = "Should the export include deleted accounts, or only the active ones?"
            out.append(Decision(sessionId: s, agent: .kimi, kind: .other, why: q, touches: "Nothing: it is a question, not an action.",
                                risk: .low, ifNo: "The agent keeps waiting for your answer.", pattern: Decision.questionPrefix + q,
                                repo: "acme/api", askedAt: now.addingTimeInterval(-15 * 60)))
        }
        if n >= 4, let s = sid("Checkout page stickers") {
            let said = """
            Done. The checkout page now shows the stickers next to each line item:

            - "New" for items added in the last 7 days
            - "Low stock" when fewer than 5 are left
            - "Back soon" for items that are out of stock

            I added snapshot tests for all three and ran the full suite: 214 passed, 0 failed.
            The sticker colours come from the design tokens, so dark mode works too.

            Two things I did not do:
            1. The cart drawer still uses the old badge; it needs the same change.
            2. The copy for "Back soon" is a placeholder; marketing may want other words.

            Want me to do the cart drawer next, or open a PR for what is here?
            """
            out.append(Decision(sessionId: s, agent: .claude, kind: .other, why: said, touches: "Nothing runs: the turn is over.",
                                risk: .low, ifNo: "The session waits.", pattern: Decision.finishedPrefix + "checkout",
                                repo: "acme/web", askedAt: now.addingTimeInterval(-22 * 60)))
        }
        if n >= 5 {
            var o = Objective(title: "Release notes for 1.9.38", doneWhen: "CHANGELOG has a 1.9.38 section and the site's download page links it",
                              repoPath: Workspace.projectsRoot + "/acme/api")
            let md = """
            ```oneroof-plan
            {"steps": [
              {"id": "s1", "title": "Collect the merged changes since 1.9.37", "agent": "claude", "account": "Claude1", "model": "sonnet", "cost": "$0.20", "prompt": "-"},
              {"id": "s2", "title": "Write the CHANGELOG section in plain words", "agent": "codex", "model": "gpt-5", "cost": "$0.35", "prompt": "-"},
              {"id": "s3", "title": "Link it from the download page", "agent": "claude", "account": "Claude2", "model": "sonnet", "cost": "$0.10", "prompt": "-"}
            ]}
            ```
            """
            o.plan = PlanParser.parse(md)
            o.status = .review
            o.createdAt = now.addingTimeInterval(-30 * 60)
            if o.plan != nil, !m.objectives.contains(where: { $0.title == o.title }) { m.saveObjective(o) }
        }
        if n >= 6 {
            LoopInboxState.shared.seedForSelfTest([LoopInbox.Item(
                id: "failed-selftest", kind: .failed, loopId: "selftest-nightly-bugs", loopTitle: "Nightly bugs",
                headline: "Stopped after 3 rounds with the same failure",
                detail: "Round 3 failed the same way as rounds 1 and 2: `swift test` exits 1 in LoginTests (timeout after 30 s). The loop stops after 3 rounds with the same failure.",
                when: now.addingTimeInterval(-45 * 60))])
            if let s = sid("Release notes") {   // an answered ask: the Decided list
                out.append(Decision(sessionId: s, agent: .gemini, kind: .runCommand, command: "npm run lint", why: "Check the notes' Markdown.",
                                    touches: "Reads docs/.", risk: .low, ifNo: "It skips the check.", pattern: "npm run lint", repo: "acme/api",
                                    askedAt: now.addingTimeInterval(-70 * 60), answeredAt: now.addingTimeInterval(-68 * 60), answer: .allowOnce))
            }
        }
        if n >= 7, let s = sid("Release notes") {
            out.append(Decision(sessionId: s, agent: .gemini, kind: .push, command: "git push origin release-notes",
                                why: "The notes are written; pushing the branch lets you open the PR.", touches: "Pushes release-notes to origin.",
                                risk: .high, ifNo: "Nothing leaves this Mac.", where_: "Last step", pattern: "git push", repo: "acme/api",
                                askedAt: now.addingTimeInterval(-2 * 60)))
        }
        m.selfTestDecisions = out
    }
}
