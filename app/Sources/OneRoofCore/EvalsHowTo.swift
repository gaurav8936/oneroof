import Foundation

/// LAB-2113 · Evals › How to (the first tab): a scene-by-scene walkthrough of what Evals is for and how to use each part.
/// The narrated version is an Agentic Engineering card (slug below) that the packaged deck may carry; One Roof authors no
/// AE content, so when the deck has the card its narration plays with these scenes, and otherwise the built-in text
/// below (help for One Roof's own screens, like docs/help) shows with "Narration coming".
public enum EvalsHowTo {
    /// The deck card that narrates this walkthrough (track: One Roof how-to).
    public static let cardSlug = "one-roof-evals-how-to"
    /// Scenes you have read (comma-separated ids), remembered per Mac.
    public static let progressKey = "evals.howto.done"
    /// Set once How to has been shown: the first visit to Evals opens How to, later visits open Overview.
    public static let seenKey = "evals.howto.seen"

    public struct Scene: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var body: String
        /// The tab this scene talks about (its "Open" button), nil for none.
        public var tab: EvalsTabV2?
        public var openLabel: String
    }

    public static let scenes: [Scene] = [
        Scene(id: "for", title: "What Evals is for: three jobs",
              body: "Evals answers one question: is this model or agent good enough for the work, and is the difference real? It does three jobs. "
                + "One: compare models on public benchmarks, sets of questions others published (GSM8K maths, Humanity's Last Exam, SWE-bench). "
                + "Two: test your own agents and models on your own work, with sets built from your repository's real bugs and their fixes. "
                + "Three: build and keep your own eval sets and judges, versioned, so next month's model is measured the same way.",
              tab: .overview, openLabel: "Open Overview"),
        Scene(id: "first", title: "A first eval in two minutes",
              body: "Open Explore, pick a Start here benchmark such as GSM8K and press Run this. In Run, keep the free stand-in model (mockllm) to see the whole loop at no cost, "
                + "then tick one cheap model and five questions. The cost shows before anything starts; Start runs it in the background.",
              tab: .explore, openLabel: "Open Explore"),
        Scene(id: "read", title: "Reading a result",
              body: "A score is right answers over all questions. The 95 % range says how much it could move if you asked other questions of the same kind: "
                + "a narrow range means the number is steady. The floor is what guessing scores. Hover any number for what it means; Learn has a lesson on each.",
              tab: .results, openLabel: "Open Results"),
        Scene(id: "compare", title: "Comparing two models or agents",
              body: "In Results, Compare puts two runs side by side on the same questions. It says whether the difference is real or could be luck, "
                + "and lists the questions where they disagree, so you can read what each answered.",
              tab: .results, openLabel: "Open Results"),
        Scene(id: "build", title: "Building your own set from a repository",
              body: "Your evals builds a set from a repository's history: each case is a real bug with the commit that fixed it. Versions keep every earlier case, "
                + "so scores on v1 and v2 stay comparable. Run your agents on it like any benchmark.",
              tab: .yourEvals, openLabel: "Open Your evals"),
        Scene(id: "judge", title: "A judge for answers code can't check",
              body: "When an answer can't be checked by code (a summary, a review), a judge model grades it against a rubric. You label a few answers yourself; "
                + "Evals measures how often the judge agrees with you, which tells you how far to trust it.",
              tab: .yourEvals, openLabel: "Open Your evals"),
        Scene(id: "who", title: "Agents on your seats, models via API",
              body: "Run can test agents on your subscription seats (Claude Code, Codex: it shows the share of the five-hour window a run takes) "
                + "or models through an API key (billed per token, capped per run). Either way the cost shows before you start.",
              tab: .run, openLabel: "Open Run"),
        Scene(id: "next", title: "What to do next, and where things live",
              body: "Overview: what you ran lately and what to try next. Your evals: your sets and judges. Explore: every benchmark, its questions and published scores. "
                + "Run: what to run, on whom, at what cost. Results: every finished run. Learn: what the numbers mean.",
              tab: .learn, openLabel: "Open Learn"),
    ]

    public static func done(_ stored: String) -> Set<String> { Set(stored.split(separator: ",").map(String.init)) }
    public static func store(_ done: Set<String>) -> String { scenes.map(\.id).filter(done.contains).joined(separator: ",") }

    /// "3 of 8 read".
    public static func progressLine(_ done: Set<String>) -> String {
        "\(scenes.filter { done.contains($0.id) }.count) of \(scenes.count) read"
    }

    /// The first scene not read yet (where Continue starts), or the first.
    public static func next(_ done: Set<String>) -> Scene { scenes.first { !done.contains($0.id) } ?? scenes[0] }

    public enum NarrationState: Equatable, Sendable {
        /// The deck has the card and it has audio: Play works, scene n plays track n.
        case playable(tracks: Int)
        /// No card or no audio in this build yet.
        case coming
    }

    public static func narration(cardPresent: Bool, tracks: Int) -> NarrationState {
        cardPresent && tracks > 0 ? .playable(tracks: tracks) : .coming
    }

    /// The track to play for a scene (clamped to the card's tracks).
    public static func track(for sceneId: String, tracks: Int) -> Int {
        guard tracks > 0 else { return 0 }
        return min(scenes.firstIndex { $0.id == sceneId } ?? 0, tracks - 1)
    }
}
