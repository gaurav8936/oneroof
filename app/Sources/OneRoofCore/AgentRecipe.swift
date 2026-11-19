import Foundation

// LAB-2329 · Agent factory F1: the recipe format. A recipe is a team of agents for a kind of task: the roles and which
// agent and model plays each, the pattern they work in, the finish line that proves the task is done, and the budget.
// The Factory place (LAB-2330) shows the library; the orchestrator (LAB-198) runs one. Your own recipes are JSON files
// in the recipes folder (`AgentRecipes.folder`), in the same shape as the built-ins below.
// Design: labs-docs/projects/lab-oneroof-enhancements/20261119_01_one-roof-roadmap-left-rail-and-agent-factory.md

/// How the roles work together.
public enum RecipePattern: String, Codable, CaseIterable, Sendable {
    /// One agent builds, a different agent reviews with set instructions; the tool enforces the review (LAB-1245).
    case makerChecker
    /// Each role is a step: plan → build → test → write up.
    case pipeline
    /// The work is split, parts run in parallel worktrees (at most `maxParallel`), then merged and checked.
    case fanOutMerge
    /// Two agents solve it, a third picks or combines.
    case twoAnswersJudge
    /// Build and check again until the finish line's check passes or the budget runs out.
    case loopUntilCheck

    public var title: String {
        switch self {
        case .makerChecker: return "Maker → checker"
        case .pipeline: return "Pipeline"
        case .fanOutMerge: return "Fan-out → merge"
        case .twoAnswersJudge: return "Two answers → judge"
        case .loopUntilCheck: return "Loop until the check passes"
        }
    }

    /// The roles a pattern needs, in the order they act. A recipe's roles must name exactly these.
    public var roleNames: [String] {
        switch self {
        case .makerChecker: return ["maker", "checker"]
        case .pipeline: return ["planner", "builder", "tester", "writer"]
        case .fanOutMerge: return ["splitter", "worker", "merger"]
        case .twoAnswersJudge: return ["first", "second", "judge"]
        case .loopUntilCheck: return ["builder", "checker"]
        }
    }

    /// The pattern drawn as steps (the recipe page shows this line).
    public var steps: String {
        switch self {
        case .makerChecker: return "maker builds → checker reviews → back to the maker until the checker passes it"
        case .pipeline: return "planner → builder → tester → writer"
        case .fanOutMerge: return "splitter → workers in parallel → merger checks the whole"
        case .twoAnswersJudge: return "first and second answer alone → judge picks or combines"
        case .loopUntilCheck: return "builder → check → builder … until green or out of budget"
        }
    }

    /// Roles whose agent must differ (a checker never reviews its own agent's work).
    public var mustDiffer: [(String, String)] {
        switch self {
        case .makerChecker: return [("maker", "checker")]
        case .twoAnswersJudge: return [("first", "second")]
        case .pipeline: return [("builder", "tester")]
        case .fanOutMerge, .loopUntilCheck: return []
        }
    }
}

/// One role on the team.
public struct RecipeRole: Codable, Equatable, Sendable {
    public var name: String
    public var agent: AgentKind
    /// The model the agent runs (nil = the agent's default).
    public var model: String?
    /// What the role does, in one line; given to the agent with the task.
    public var does: String
    /// Folders the role may write in ("worktree" = its own worktree only). Empty = read only.
    public var writes: [String]
    public init(name: String, agent: AgentKind, model: String? = nil, does: String, writes: [String] = ["worktree"]) {
        self.name = name; self.agent = agent; self.model = model; self.does = does; self.writes = writes
    }
}

/// The check that proves the task is done, and where the result goes.
public struct RecipeFinishLine: Codable, Equatable, Sendable {
    /// A command that exits 0 when the task is done (tests, a gate), run in the task's worktree.
    public var check: String
    /// Where the result goes: "qa" (the ticket moves to QA with an evidence comment), "pr", "report".
    public var result: String
    public init(check: String, result: String) { self.check = check; self.result = result }
}

/// What a run may spend before it stops.
public struct RecipeBudget: Codable, Equatable, Sendable {
    public var minutes: Int
    public var dollars: Double
    /// Rounds for the patterns that repeat (maker → checker, loop until the check passes).
    public var rounds: Int
    /// Parallel parts at once for fan-out (the fleet guard allows 3 lanes).
    public var maxParallel: Int
    public init(minutes: Int, dollars: Double, rounds: Int = 1, maxParallel: Int = 1) {
        self.minutes = minutes; self.dollars = dollars; self.rounds = rounds; self.maxParallel = maxParallel
    }
}

public struct AgentRecipe: Codable, Equatable, Identifiable, Sendable {
    /// Format version; a file with a newer version is skipped with a note, never misread.
    public static let formatVersion = 1
    public static let maxParallelLanes = 3

    public var format: Int
    public var id: String
    public var name: String
    /// What kind of task the team is for, in one line.
    public var summary: String
    public var pattern: RecipePattern
    public var roles: [RecipeRole]
    public var finishLine: RecipeFinishLine
    public var budget: RecipeBudget
    /// Built in (ships with One Roof) or your own file.
    public var builtIn: Bool

    public init(id: String, name: String, summary: String, pattern: RecipePattern, roles: [RecipeRole],
                finishLine: RecipeFinishLine, budget: RecipeBudget, builtIn: Bool = false) {
        self.format = Self.formatVersion; self.id = id; self.name = name; self.summary = summary; self.pattern = pattern
        self.roles = roles; self.finishLine = finishLine; self.budget = budget; self.builtIn = builtIn
    }

    public func role(_ name: String) -> RecipeRole? { roles.first { $0.name == name } }

    /// The agents the team uses, in role order, each once.
    public var agents: [AgentKind] { roles.map(\.agent).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }

    /// What is wrong with the recipe, in plain words; empty = it can run.
    public var problems: [String] {
        var out: [String] = []
        if format > Self.formatVersion { out.append("made by a newer One Roof (format \(format)); update One Roof to use it") }
        if id.isEmpty || id.contains(where: { !($0.isLetter || $0.isNumber || $0 == "-") }) { out.append("id must be letters, digits and dashes") }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("no name") }
        let names = roles.map(\.name)
        if Set(names).count != names.count { out.append("two roles share a name") }
        let want = pattern.roleNames
        let missing = want.filter { !names.contains($0) }, extra = names.filter { !want.contains($0) }
        if !missing.isEmpty { out.append("\(pattern.title) needs the role\(missing.count == 1 ? "" : "s") \(missing.joined(separator: ", "))") }
        if !extra.isEmpty { out.append("\(pattern.title) has no role \(extra.joined(separator: ", "))") }
        for r in roles where !r.agent.isAgent { out.append("role \(r.name) is a plain shell, not an agent") }
        for r in roles where r.does.trimmingCharacters(in: .whitespaces).isEmpty { out.append("role \(r.name) does not say what it does") }
        for (a, b) in pattern.mustDiffer {
            if let x = role(a), let y = role(b), x.agent == y.agent, x.model == y.model {
                out.append("\(a) and \(b) are the same agent and model; a check by the same agent proves little")
            }
        }
        if finishLine.check.trimmingCharacters(in: .whitespaces).isEmpty { out.append("no finish line check") }
        if !["qa", "pr", "report"].contains(finishLine.result) { out.append("result must be qa, pr or report") }
        if budget.minutes <= 0 { out.append("budget needs minutes") }
        if budget.dollars <= 0 { out.append("budget needs a dollar cap") }
        if budget.rounds < 1 { out.append("rounds must be at least 1") }
        if [.makerChecker, .loopUntilCheck].contains(pattern) && budget.rounds < 2 { out.append("\(pattern.title) needs at least 2 rounds") }
        if budget.maxParallel < 1 || budget.maxParallel > Self.maxParallelLanes { out.append("parallel parts must be 1 to \(Self.maxParallelLanes)") }
        if pattern == .fanOutMerge && budget.maxParallel < 2 { out.append("fan-out needs at least 2 parallel parts") }
        return out
    }

    public var canRun: Bool { problems.isEmpty }

    /// One line for the library: pattern · agents · budget.
    public var line: String {
        let money = budget.dollars == budget.dollars.rounded() ? "$\(Int(budget.dollars))" : String(format: "$%.2f", budget.dollars)
        return "\(pattern.title) · \(agents.map(\.displayName).joined(separator: " + ")) · up to \(budget.minutes) min, \(money)"
    }
}

/// The recipe library: the five built-ins plus your own files.
public enum AgentRecipes {
    /// Your own recipes: one JSON file per recipe.
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OneRoof/recipes", isDirectory: true)
    }

    public static let builtIn: [AgentRecipe] = [
        AgentRecipe(id: "maker-checker", name: "Build it, another agent checks it",
                    summary: "A ticket's change, built by Claude and reviewed by Codex before it goes to QA.",
                    pattern: .makerChecker,
                    roles: [RecipeRole(name: "maker", agent: .claude, model: "opus", does: "Build the change the ticket asks for, with tests, in the worktree."),
                            RecipeRole(name: "checker", agent: .codex, does: "Review the maker's diff against the ticket's done-when: bugs, missing tests, scope creep. Pass or list what to fix.", writes: [])],
                    finishLine: RecipeFinishLine(check: "swift test", result: "qa"),
                    budget: RecipeBudget(minutes: 90, dollars: 15, rounds: 3), builtIn: true),
        AgentRecipe(id: "ticket-pipeline", name: "Ticket from plan to write-up",
                    summary: "A well-defined ticket: plan it, build it, test it, write the evidence comment.",
                    pattern: .pipeline,
                    roles: [RecipeRole(name: "planner", agent: .claude, model: "opus", does: "Read the ticket and the code; write the steps and the check that proves each.", writes: []),
                            RecipeRole(name: "builder", agent: .claude, model: "sonnet", does: "Do the planner's steps in the worktree."),
                            RecipeRole(name: "tester", agent: .codex, does: "Run the checks, try to break the change, add the missing tests."),
                            RecipeRole(name: "writer", agent: .claude, model: "haiku", does: "Write the evidence comment: what changed, how it was checked, what is left.", writes: [])],
                    finishLine: RecipeFinishLine(check: "swift test", result: "qa"),
                    budget: RecipeBudget(minutes: 120, dollars: 20), builtIn: true),
        AgentRecipe(id: "bug-sweep", name: "Sweep a list of small bugs",
                    summary: "Many small, separate bugs: one worktree each, three at a time, merged and tested together.",
                    pattern: .fanOutMerge,
                    roles: [RecipeRole(name: "splitter", agent: .claude, model: "sonnet", does: "Split the list into parts that touch different files.", writes: []),
                            RecipeRole(name: "worker", agent: .kimi, does: "Fix one part in its own worktree, with a test."),
                            RecipeRole(name: "merger", agent: .claude, model: "opus", does: "Merge the parts, resolve conflicts, run the whole suite.")],
                    finishLine: RecipeFinishLine(check: "swift test", result: "pr"),
                    budget: RecipeBudget(minutes: 120, dollars: 25, maxParallel: 3), builtIn: true),
        AgentRecipe(id: "second-opinion", name: "Two answers and a judge",
                    summary: "A design question or a hard bug: two agents answer alone, a third picks or combines.",
                    pattern: .twoAnswersJudge,
                    roles: [RecipeRole(name: "first", agent: .claude, model: "opus", does: "Answer the question with evidence from the code.", writes: []),
                            RecipeRole(name: "second", agent: .codex, does: "Answer the same question alone, with evidence from the code.", writes: []),
                            RecipeRole(name: "judge", agent: .gemini, does: "Compare the two answers point by point; pick one or combine them, and say why.", writes: [])],
                    finishLine: RecipeFinishLine(check: "test -s answer.md", result: "report"),
                    budget: RecipeBudget(minutes: 45, dollars: 8), builtIn: true),
        AgentRecipe(id: "fix-until-green", name: "Fix until the tests pass",
                    summary: "A failing test or gate: fix and re-run until it is green or the budget runs out.",
                    pattern: .loopUntilCheck,
                    roles: [RecipeRole(name: "builder", agent: .claude, model: "sonnet", does: "Read the failure, change the code (never the test's expectation), re-run."),
                            RecipeRole(name: "checker", agent: .codex, does: "Confirm the fix is real: the test still checks what it did before.", writes: [])],
                    finishLine: RecipeFinishLine(check: "swift test", result: "qa"),
                    budget: RecipeBudget(minutes: 60, dollars: 10, rounds: 5), builtIn: true),
    ]

    public struct Loaded: Equatable, Sendable {
        public var recipes: [AgentRecipe]
        /// Files that could not be read, with why.
        public var skipped: [String]
    }

    /// Your own recipes from `folder` (any `.json`), after the built-ins; a file that cannot be read is skipped with a
    /// note. An own recipe never replaces a built-in of the same id (it is skipped with a note).
    public static func load(from dir: URL = folder) -> Loaded {
        var out = builtIn, skipped: [String] = []
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for f in files {
            guard let data = try? Data(contentsOf: f) else { skipped.append("\(f.lastPathComponent): cannot read"); continue }
            guard var r = try? JSONDecoder().decode(AgentRecipe.self, from: data) else { skipped.append("\(f.lastPathComponent): not a recipe"); continue }
            if r.format > AgentRecipe.formatVersion { skipped.append("\(f.lastPathComponent): made by a newer One Roof"); continue }
            if out.contains(where: { $0.id == r.id }) { skipped.append("\(f.lastPathComponent): id \(r.id) is already used"); continue }
            r.builtIn = false
            out.append(r)
        }
        return Loaded(recipes: out, skipped: skipped)
    }

    /// A recipe as the JSON you would save in `folder` (pretty, keys sorted), the starting point for your own.
    public static func json(_ r: AgentRecipe) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        var r = r; r.builtIn = false
        return (try? e.encode(r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
