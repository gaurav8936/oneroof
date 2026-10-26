import Foundation
@testable import OneRoofCore

// LAB-1257 · test fixture only. Until 1.9.0 One Roof hard-coded the Learn bands, the plain track names and the By-kind
// groups in LearnDeck.swift; they now come from the deck's catalog. `LearnDeckFixture.bands / trackNames / kinds` are those
// 1.8.2 constants, kept here so a test proves the catalog the deck repository now builds reads back as exactly the same.
// `catalogJSON` is the relevant part of that catalog (bands, kinds, tracks with names) as built by build-catalog.py.
enum LearnDeckFixture {
    static let bands: [DeckBand] = [
        DeckBand(id: "context", n: "01", zone: "BEFORE THE WORK", title: "Context", sub: "What the agent knows at the first prompt",
                 def: "Every session starts cold. What it knows is whatever it loaded: instruction files, notes, the last handoff. Context is a structure on disk, designed once and then enforced.",
                 tracks: ["foundations", "vault", "influences"], key: ["context-as-structure", "knowledge-notes", "docs-phonebook", "the-2x2-map"],
                 posts: ["agentic-engineering", "one-workspace"]),
        DeckBand(id: "loops", n: "02", zone: "BEFORE THE WORK", title: "Loops", sub: "A unit of work with a stop condition",
                 def: "Hand the agent a loop, not a task: a goal written as an end state, a check that runs without a person, and a condition that says stop, whether or not it succeeded.",
                 tracks: ["rhythms", "pipeline", "model-craft", "modality"], key: ["loops-first", "done-when", "feedback-loop", "orchestration"],
                 posts: ["loops-with-a-stop-condition", "one-roof-builds-one-roof"]),
        DeckBand(id: "evidence", n: "03", zone: "AFTER THE WORK", title: "Evidence", sub: "Proof the unit is done",
                 def: "Agents report success in the same fluent voice whether or not they succeeded. Separate the claim from the proof, and put the proof where the agent can't write it.",
                 tracks: ["ship", "debug", "safety"], key: ["evidence-check", "test-first", "smoke-prod", "audit-trail"],
                 posts: ["evidence-not-confidence", "one-roof-builds-one-roof"]),
        DeckBand(id: "procedure", n: "04", zone: "AFTER THE WORK", title: "Procedure", sub: "What the next session inherits",
                 def: "A lesson that lives in one session dies with it. Written as a skill, it reaches every agent at its next start; narrated as a card, it teaches a person the same thing.",
                 tracks: ["doctrine", "comms", "infra", "play"], key: ["compounding-instincts", "gotcha-log", "decision-record", "spawn-doctrine"],
                 posts: ["one-library-every-agent"]),
    ]

    static let trackNames: [String: (name: String, question: String)] = [
        "foundations": ("Big ideas", "What makes agentic engineering different?"),
        "vault": ("Notes & memory", "Where does what we know live?"),
        "influences": ("People worth hearing", "Whose thinking is this built on?"),
        "rhythms": ("Daily loops", "What runs every session and every night?"),
        "pipeline": ("Ticket to merged PR", "How does work move from idea to code?"),
        "model-craft": ("Working with models", "How do I get more out of the model itself?"),
        "modality": ("Beyond text", "Voice, vision, documents, computer use."),
        "ship": ("Shipping", "How do I know it is live, and right?"),
        "debug": ("Debugging", "Something's wrong. Where?"),
        "safety": ("Guardrails", "What stops an agent doing damage?"),
        "doctrine": ("How we work", "The rules a team of agents follows."),
        "comms": ("Messages & channels", "How agents talk to people."),
        "infra": ("Dev environment", "Repos, git, worktrees, planning."),
        "play": ("Walkthroughs", "Low-stakes animated tours. No grading."),
    ]

    static let kinds: [(title: String, sub: String, tracks: [String])] = [
        ("Ideas & rules", "The thinking, and the rules that follow from it", ["foundations", "doctrine"]),
        ("Skills agents run", "Procedures you can hand to an agent today", ["rhythms", "pipeline", "ship", "debug", "safety", "model-craft", "modality", "comms", "vault", "infra"]),
        ("People", "The voices the ideas come from", ["influences"]),
        ("Walkthroughs", "Tours, for fun", ["play"]),
    ]

    static let catalogJSON = #"""
{"version": "0.2.0", "suits": [{"id": "spades", "symbol": "♠", "color": "#1e293b", "soft": "#f8fafc", "label": "Conceptual · the ideas", "tracks": ["foundations", "doctrine", "rhythms"]}, {"id": "hearts", "symbol": "♥", "color": "#be123c", "soft": "#fff1f2", "label": "Delivery · the work", "tracks": ["pipeline", "model-craft", "modality", "ship"]}, {"id": "diamonds", "symbol": "♦", "color": "#b45309", "soft": "#fffbeb", "label": "Support · the scaffolding", "tracks": ["comms", "vault", "debug", "safety"]}, {"id": "clubs", "symbol": "♣", "color": "#047857", "soft": "#ecfdf5", "label": "Supporting · the context", "tracks": ["influences", "play", "infra"]}], "bands": [{"id": "context", "n": "01", "zone": "BEFORE THE WORK", "title": "Context", "subtitle": "What the agent knows at the first prompt", "definition": "Every session starts cold. What it knows is whatever it loaded: instruction files, notes, the last handoff. Context is a structure on disk, designed once and then enforced.", "tracks": ["foundations", "vault", "influences"], "start_here": ["context-as-structure", "knowledge-notes", "docs-phonebook", "the-2x2-map"], "posts": ["agentic-engineering", "one-workspace"]}, {"id": "loops", "n": "02", "zone": "BEFORE THE WORK", "title": "Loops", "subtitle": "A unit of work with a stop condition", "definition": "Hand the agent a loop, not a task: a goal written as an end state, a check that runs without a person, and a condition that says stop, whether or not it succeeded.", "tracks": ["rhythms", "pipeline", "model-craft", "modality"], "start_here": ["loops-first", "done-when", "feedback-loop", "orchestration"], "posts": ["loops-with-a-stop-condition", "one-roof-builds-one-roof"]}, {"id": "evidence", "n": "03", "zone": "AFTER THE WORK", "title": "Evidence", "subtitle": "Proof the unit is done", "definition": "Agents report success in the same fluent voice whether or not they succeeded. Separate the claim from the proof, and put the proof where the agent can't write it.", "tracks": ["ship", "debug", "safety"], "start_here": ["evidence-check", "test-first", "smoke-prod", "audit-trail"], "posts": ["evidence-not-confidence", "one-roof-builds-one-roof"]}, {"id": "procedure", "n": "04", "zone": "AFTER THE WORK", "title": "Procedure", "subtitle": "What the next session inherits", "definition": "A lesson that lives in one session dies with it. Written as a skill, it reaches every agent at its next start; narrated as a card, it teaches a person the same thing.", "tracks": ["doctrine", "comms", "infra", "play"], "start_here": ["compounding-instincts", "gotcha-log", "decision-record", "spawn-doctrine"], "posts": ["one-library-every-agent"]}], "kinds": [{"id": "ideas", "title": "Ideas & rules", "subtitle": "The thinking, and the rules that follow from it", "tracks": ["foundations", "doctrine"]}, {"id": "skills", "title": "Skills agents run", "subtitle": "Procedures you can hand to an agent today", "tracks": ["rhythms", "pipeline", "ship", "debug", "safety", "model-craft", "modality", "comms", "vault", "infra"]}, {"id": "people", "title": "People", "subtitle": "The voices the ideas come from", "tracks": ["influences"]}, {"id": "walkthroughs", "title": "Walkthroughs", "subtitle": "Tours, for fun", "tracks": ["play"]}], "tracks": [{"id": "foundations", "suit": "spades", "intro": "The strategic ideas — what makes agentic engineering different.", "name": "Big ideas", "question": "What makes agentic engineering different?", "cards": []}, {"id": "doctrine", "suit": "spades", "intro": "The methodology — how you work when you work agentically.", "name": "How we work", "question": "The rules a team of agents follows.", "cards": []}, {"id": "rhythms", "suit": "spades", "intro": "The heartbeat — session, instinct, mission, nightly, goal loops.", "name": "Daily loops", "question": "What runs every session and every night?", "cards": []}, {"id": "pipeline", "suit": "hearts", "intro": "The delivery conveyor — ticket in, merged PR out.", "name": "Ticket to merged PR", "question": "How does work move from idea to code?", "cards": []}, {"id": "model-craft", "suit": "hearts", "intro": "The craft of working with models — runtime, memory, retrieval, evals.", "name": "Working with models", "question": "How do I get more out of the model itself?", "cards": []}, {"id": "modality", "suit": "hearts", "intro": "Beyond text — vision, voice, documents, computer-use.", "name": "Beyond text", "question": "Voice, vision, documents, computer use.", "cards": []}, {"id": "ship", "suit": "hearts", "intro": "The last mile — CI/CD, promotion, morning golden, backup.", "name": "Shipping", "question": "How do I know it is live, and right?", "cards": []}, {"id": "comms", "suit": "diamonds", "intro": "How agents and humans talk — Slack, Discord, email, Teams, GitHub.", "name": "Messages & channels", "question": "How agents talk to people.", "cards": []}, {"id": "vault", "suit": "diamonds", "intro": "The knowledge layer — Markdown notes read in Zibajoon Knowledge, phone books, reports, brand, design.", "name": "Notes & memory", "question": "Where does what we know live?", "cards": []}, {"id": "debug", "suit": "diamonds", "intro": "Something's wrong. Find it. Fix it.", "name": "Debugging", "question": "Something's wrong. Where?", "cards": []}, {"id": "safety", "suit": "diamonds", "intro": "The guardrails that keep the stack trustworthy.", "name": "Guardrails", "question": "What stops an agent doing damage?", "cards": []}, {"id": "influences", "suit": "clubs", "intro": "The canon of voices behind the ideas.", "name": "People worth hearing", "question": "Whose thinking is this built on?", "cards": []}, {"id": "play", "suit": "clubs", "intro": "Low-stakes animated walkthroughs. No grading.", "name": "Walkthroughs", "question": "Low-stakes animated tours. No grading.", "cards": []}, {"id": "infra", "suit": "clubs", "intro": "Dev-env infrastructure + hygiene — repos, git, orchestrator, planning.", "name": "Dev environment", "question": "Repos, git, worktrees, planning.", "cards": []}], "cards": [{"slug": "done-when", "track": "rhythms", "title": "Done when"}]}
"""#
}
