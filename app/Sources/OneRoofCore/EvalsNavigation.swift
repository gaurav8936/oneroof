import Foundation

// LAB-2242 · Evals v2 (One Roof 2.0.4): six tabs, five drill-downs and two sheets (handover shared/NAVIGATION.md,
// SCREEN_MAP.md). Pure names and mappings only; the views live in Sources/OneRoof/UI/Evals/.

/// The six tabs, in the handover's order: Overview opens first. ⌃⌥1 … ⌃⌥6.
public enum EvalsTabV2: String, CaseIterable, Identifiable, Sendable {
    case overview, compare, changes, realHistory, ourTasks, benchmarks
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .overview: return "Overview"; case .compare: return "Compare"; case .changes: return "Changes"
        case .realHistory: return "Real history"; case .ourTasks: return "Our tasks"; case .benchmarks: return "Public benchmarks"
        }
    }
    /// ⌃⌥1…⌃⌥6 (⌘1…5 and ⌥⌘1…9 are taken by group-by and workspaces, KeymapV2).
    public var keyDigit: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }
    /// The tab's own screen.
    public var screen: EvalsScreen {
        switch self {
        case .overview: return .overview; case .compare: return .compare; case .changes: return .changes
        case .realHistory: return .realHistory; case .ourTasks: return .ourTasks; case .benchmarks: return .benchmarks
        }
    }
    /// ONEROOF_SELFTEST_EVALS_TAB values (new and old): see `EvalsScreen.selfTest`.
    public static func selfTest(_ v: String) -> EvalsSelfTest? { EvalsScreen.selfTest(v) }
}

/// The 2.0.3 tabs (How to · Overview · Your evals · Explore · Run · Results · Learn). Kept so the 2.0.3 views (still in
/// the app until the screen lanes replace them) and their links keep working; each maps to its 2.0.4 home.
public enum EvalsLegacyTab: String, CaseIterable, Sendable {
    case howTo, overview, yourEvals, explore, run, results, learn
    public var title: String {
        switch self {
        case .howTo: return "How to"; case .overview: return "Overview"; case .yourEvals: return "Your evals"; case .explore: return "Explore"
        case .run: return "Run"; case .results: return "Results"; case .learn: return "Learn"
        }
    }
    /// Where the old tab lives now (NO_REGRESSION.md): How to and Learn → Lessons, Your evals → Our tasks, Explore →
    /// Public benchmarks, Run → Set up a test, Results → Compare.
    public var home: EvalsScreen {
        switch self {
        case .howTo, .learn: return .lessons
        case .overview: return .overview
        case .yourEvals: return .ourTasks
        case .explore: return .benchmarks
        case .run: return .setup
        case .results: return .compare
        }
    }
}

/// Every Evals screen (SCREEN_MAP.md): six tabs, five drill-downs, two sheets.
public enum EvalsScreen: String, CaseIterable, Sendable {
    case overview, compare, oneTest, allResults, changes, realHistory, ourTasks, oneTask, grader, benchmarks, oneBenchmark, setup, lessons

    public enum Kind: Sendable { case tab, drill, sheet }
    public var kind: Kind {
        switch self {
        case .overview, .compare, .changes, .realHistory, .ourTasks, .benchmarks: return .tab
        case .oneTest, .allResults, .oneTask, .grader, .oneBenchmark: return .drill
        case .setup, .lessons: return .sheet
        }
    }
    /// The tab a screen belongs to (a drill-down's parent; nil for the sheets, which open over any tab).
    public var tab: EvalsTabV2? {
        switch self {
        case .overview: return .overview
        case .compare, .oneTest, .allResults: return .compare
        case .changes: return .changes
        case .realHistory: return .realHistory
        case .ourTasks, .oneTask, .grader: return .ourTasks
        case .benchmarks, .oneBenchmark: return .benchmarks
        case .setup, .lessons: return nil
        }
    }
    public var title: String {
        switch self {
        case .oneTest: return "One test"
        case .allResults: return "All results"
        case .oneTask: return "One task"
        case .grader: return "Check the grader"
        case .oneBenchmark: return "A public benchmark"
        case .setup: return "Set up a test"
        case .lessons: return "Lessons"
        default: return tab?.title ?? rawValue
        }
    }
    /// The breadcrumb's "‹ parent" on a drill-down.
    public var backTitle: String? { kind == .drill ? tab?.title : nil }

    /// The kebab-case self-test name ("one-test", "real-history").
    public var selfTestName: String {
        switch self {
        case .overview: return "overview"; case .compare: return "compare"; case .oneTest: return "one-test"
        case .allResults: return "all-results"; case .changes: return "changes"; case .realHistory: return "real-history"
        case .ourTasks: return "our-tasks"; case .oneTask: return "one-task"; case .grader: return "grader"
        case .benchmarks: return "benchmarks"; case .oneBenchmark: return "one-benchmark"; case .setup: return "setup"; case .lessons: return "lessons"
        }
    }

    /// ONEROOF_SELFTEST_EVALS_TAB: the 2.0.4 names, and every 2.0.3 / 1.9.37 name mapped to its new home. `part` is the
    /// sub-view: questions · scores · runs (a benchmark), sheet (setup pre-filled), how-to (Lessons' walkthrough).
    public static func selfTest(_ raw: String) -> EvalsSelfTest? {
        let v = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let s = allCases.first(where: { $0.selfTestName == v }) { return EvalsSelfTest(screen: s, part: nil) }
        switch v {
        // 2.0.4 spellings
        case "realhistory", "history": return .init(screen: .realHistory, part: nil)
        case "ourtasks", "tasks": return .init(screen: .ourTasks, part: nil)
        case "allresults": return .init(screen: .allResults, part: nil)
        case "onetest", "test": return .init(screen: .oneTest, part: nil)
        case "onetask", "task": return .init(screen: .oneTask, part: nil)
        case "onebenchmark", "benchmark": return .init(screen: .oneBenchmark, part: nil)
        case "public-benchmarks": return .init(screen: .benchmarks, part: nil)
        case "set-up", "setup-sheet", "new-test": return .init(screen: .setup, part: nil)
        // 2.0.3 and 1.9.37 names → their 2.0.4 home
        case "how-to", "howto": return .init(screen: .lessons, part: "how-to")
        case "your-evals", "build", "yourevals": return .init(screen: .ourTasks, part: nil)
        case "judge": return .init(screen: .grader, part: nil)
        case "explore", "catalog": return .init(screen: .benchmarks, part: nil)
        case "question", "questions": return .init(screen: .oneBenchmark, part: "questions")
        case "scores": return .init(screen: .oneBenchmark, part: "scores")
        case "your-runs": return .init(screen: .oneBenchmark, part: "runs")
        case "run", "runs": return .init(screen: .setup, part: nil)
        case "sheet": return .init(screen: .setup, part: "sheet")
        case "results": return .init(screen: .compare, part: nil)
        case "run-detail", "one-run": return .init(screen: .oneTest, part: nil)
        case "all-by-all", "allbyall", "matrix": return .init(screen: .allResults, part: nil)
        case "xray", "x-ray": return .init(screen: .realHistory, part: nil)
        case "learn": return .init(screen: .lessons, part: nil)
        default: return nil
        }
    }
}

/// What a self-test name opens: a screen and, for some, a part of it.
public struct EvalsSelfTest: Equatable, Sendable {
    public var screen: EvalsScreen
    public var part: String?
    public init(screen: EvalsScreen, part: String?) { self.screen = screen; self.part = part }
    /// The tab shown under it (a sheet opens over Overview).
    public var tab: EvalsTabV2 { screen.tab ?? .overview }
}
