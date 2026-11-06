import XCTest
@testable import OneRoofCore

/// LAB-2261 · Evals v3 lane A: Set up a test's One-shot · Agent switch (+ Rules, D4), All results' Kind (E4.2) and
/// Our tasks' "tested as" chips (D5).
final class EvalsSetupKindTests: XCTestCase {
    private let own = "/e/sets/oneroof/v2/own_oneroof_v2.py"

    // E7.1 · the switch ⇄ the 2.0.4 layer, both ways.
    func test_LAB2261_switch_maps_onto_the_old_layers() {
        XCTAssertEqual(EvalSetupKindChoice(layer: .model), .init(kind: .oneShot))
        XCTAssertEqual(EvalSetupKindChoice(layer: .agentModel), .init(kind: .agent, rules: .clean))
        XCTAssertEqual(EvalSetupKindChoice(layer: .full), .init(kind: .agent, rules: .withRules))
        for l in EvalStamp.Layer.allCases { XCTAssertEqual(EvalSetupKindChoice(layer: l).layer, l) }
        XCTAssertEqual(EvalSetupKindChoice(kind: .oneShot, rules: .clean).layer, .model)   // rules never matter for one-shot
        XCTAssertEqual(EvalSetupKindChoice.default, .init(kind: .agent, rules: .withRules))  // D4: default on
        XCTAssertEqual(EvalJobKind.allCases.map(\.short), ["One-shot", "Agent"])
        XCTAssertEqual(EvalSetupRules.allCases.map(\.title), ["With our rules", "Clean (no rules)"])
    }

    func test_LAB2261_rows_shown_under_each_position() {
        let m = EvalSetupChoice.model("anthropic/claude-opus-5-5")
        let clean = EvalSetupChoice.seat("claude_code")
        let ours = EvalSetupChoice.seat("claude_code", rules: true)
        let api = EvalSetupChoice.apiAgent("codex_cli", model: "openai/gpt-5")
        let one = EvalSetupKindChoice(kind: .oneShot)
        XCTAssertEqual([m, clean, ours, api].filter(one.shows), [m])
        XCTAssertEqual([m, clean, ours, api].filter(EvalSetupKindChoice(kind: .agent, rules: .clean).shows), [clean, api])
        XCTAssertEqual([m, clean, ours, api].filter(EvalSetupKindChoice(kind: .agent, rules: .withRules).shows), [ours])
        XCTAssertEqual(EvalSetupKindChoice.count([m, clean, ours, api], kind: .oneShot), 1)
        XCTAssertEqual(EvalSetupKindChoice.count([m, clean, ours, api], kind: .agent), 3)
        XCTAssertEqual(EvalSetupKindChoice.count([m, clean, ours, api], rules: .withRules), 1)
        XCTAssertEqual(EvalSetupKindChoice.count([m, clean, ours, api], rules: .clean), 2)
    }

    // The engine call contract: old full == agent + with our rules; old agent_model == agent + clean, byte for byte.
    func test_LAB2261_run_arguments_unchanged_for_the_same_choices() {
        let plan = EvalRunPlan(tasks: [own], models: [], limit: 10, epochs: 2)
        let full = EvalSetupChoice(agent: "claude_code", model: "claude-opus-5-5", runsOn: .seat, rules: true)
        let agentModel = EvalSetupChoice(agent: "claude_code", model: nil, runsOn: .seat, rules: false)
        let viaSwitchOn = EvalSetupChoice.seat("claude_code", model: "claude-opus-5-5", rules: EvalSetupKindChoice(kind: .agent, rules: .withRules).layer == .full)
        let viaSwitchOff = EvalSetupChoice.seat("claude_code", rules: EvalSetupKindChoice(kind: .agent, rules: .clean).layer == .full)
        XCTAssertEqual(viaSwitchOn.runArguments(task: own, plan: plan), full.runArguments(task: own, plan: plan))
        XCTAssertEqual(viaSwitchOff.runArguments(task: own, plan: plan), agentModel.runArguments(task: own, plan: plan))
        XCTAssertEqual(full.runArguments(task: own, plan: plan),
                       ["run", own, "--agent", "claude_code", "--seat", "C1", "--seat-limit", "90", "--limit", "10",
                        "--model", "claude-opus-5-5", "--rules", "on", "--epochs", "2", "--background", "--json"])
        XCTAssertFalse(agentModel.runArguments(task: own, plan: plan).contains("--rules"))
    }

    // A pre-filled plan: agents → Agent with their rules; only models → One-shot.
    func test_LAB2261_prefill_opens_on_the_right_position() {
        var p = EvalRunPlan(tasks: [own], models: ["anthropic/claude-haiku-5-5"])
        XCTAssertEqual(EvalSetupKindChoice.opening(EvalSetupChoice.from(p)), .init(kind: .oneShot))
        p.agents = ["claude_code"]   // Test them / Run both agents: a 2.0.3 seat agent is clean
        XCTAssertEqual(EvalSetupKindChoice.opening(EvalSetupChoice.from(p)), .init(kind: .agent, rules: .clean))
        p.setups = [.model("anthropic/claude-haiku-5-5"), .seat("codex_cli", rules: true)]   // Test again on a rules-on setup
        XCTAssertEqual(EvalSetupKindChoice.opening(EvalSetupChoice.from(p)), .init(kind: .agent, rules: .withRules))
        XCTAssertNil(EvalSetupKindChoice.opening([]))
    }

    func test_LAB2261_defaults_turn_our_rules_on_and_never_start_zero() {
        let d = EvalSetupKindChoice.defaults(task: own, seatAgents: ["claude_code", "codex_cli"])
        XCTAssertEqual(d.choice, .init(kind: .agent, rules: .withRules))
        XCTAssertEqual(d.choices, [.seat("claude_code", rules: true)])
        let pub = EvalSetupKindChoice.defaults(task: "gsm8k", seatAgents: ["claude_code"])
        XCTAssertEqual(pub.choice, .init(kind: .oneShot))
        XCTAssertEqual(pub.choices, [.model("mockllm/model")])
        XCTAssertEqual(EvalSetupKindChoice.defaults(task: nil, seatAgents: []).choices.count, 1)
    }

    // E4.2 · Kind per result and per grid row.
    func test_LAB2261_result_kind() throws {
        let rs = try JSONDecoder().decode([EvalResult].self, from: Data(#"""
        [{"id": "a", "task": "own_oneroof_v2", "set_name": "oneroof", "set_version": 2, "status": "done", "model": "anthropic/claude-opus-5-5", "metrics": [], "contestant": {"kind": "model", "id": "o", "name": "o"}},
         {"id": "b", "task": "own_oneroof_v2", "set_name": "oneroof", "status": "done", "model": "seat/claude_code", "agent": "claude_code", "metrics": [], "contestant": {"kind": "agent", "id": "seat:claude_code", "name": "Claude Code · C1"}},
         {"id": "c", "task": "gsm8k", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [], "contestant": {"kind": "model", "id": "h", "name": "h"}},
         {"id": "d", "task": "swe_bench_verified", "status": "done", "model": "openai/gpt-5", "metrics": [], "contestant": {"kind": "agent", "id": "codex@gpt-5", "name": "Codex · gpt-5"}},
         {"id": "e", "task": "own_oneroof_v1", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [], "contestant": {"kind": "model", "id": "h", "name": "h"}},
         {"id": "f", "task": "judge_oneroof", "status": "done", "model": "anthropic/claude-haiku-5-5", "metrics": [], "contestant": {"kind": "model", "id": "h", "name": "h"}}]
        """#.utf8))
        XCTAssertEqual(rs.map(EvalResultKind.of), [.oneShot, .agent, .publicModel, .publicAgent, .oneShot, .oneShot])
        XCTAssertEqual(rs.map { EvalResultKind.of($0).title }, ["one-shot", "agent", "public model", "public agent", "one-shot", "one-shot"])
        XCTAssertEqual(EvalResultKind.row([rs[0], rs[4]]), .oneShot)
        XCTAssertEqual(EvalResultKind.row([rs[0], rs[2]]), .oneShot)     // ours + public, same who-answered: the job kind
        XCTAssertEqual(EvalResultKind.row([rs[2]]), .publicModel)
        XCTAssertEqual(EvalResultKind.row([rs[3]]), .publicAgent)
        XCTAssertNil(EvalResultKind.row([]))
    }

    // E5.1 · D5: layer chips read as "tested as" chips (the chip data is unchanged).
    func test_LAB2261_tested_as_chips() {
        let chips = EvalTaskCoverage.chips(name: "oneroof", version: 2, results: [], runs: [])
        XCTAssertEqual(chips.map(\.testedAs), ["model", "agent clean", "agent with our rules"])
        XCTAssertEqual(chips.map(\.kind), [.oneShot, .agent, .agent])
    }
}
