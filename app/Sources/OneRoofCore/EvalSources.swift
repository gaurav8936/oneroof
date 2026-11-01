import Foundation

// LAB-2117 · where each benchmark's data comes from, its licence, and whether it is gated on Hugging Face. One Roof
// never ships, pre-downloads or reuses anyone else's copy or token: the data downloads to this Mac on first use, and a
// gated set stays locked until the user signs in with their own Hugging Face account and accepts the dataset's terms.
// Licences checked on 2026-11-01 against each dataset's Hugging Face card (or the maker's repository).

public struct EvalDataSource: Equatable, Sendable {
    /// The inspect_evals folder (the benchmark's id in the catalog).
    public var folder: String
    /// Where the questions come from: a Hugging Face dataset id, or the maker's host.
    public var origin: String
    public var url: String
    /// The licence as the dataset states it; "not stated" when the card gives none.
    public var licence: String
    /// Gated on Hugging Face: needs the user's own account and accepted terms.
    public var gated: Bool

    public init(folder: String, origin: String, url: String, licence: String, gated: Bool = false) {
        self.folder = folder; self.origin = origin; self.url = url; self.licence = licence; self.gated = gated
    }

    public var isHuggingFace: Bool { url.hasPrefix("https://huggingface.co/") }
    /// The page where the user accepts a gated dataset's terms (its Hugging Face page).
    public var termsURL: String? { gated ? url : nil }
}

public enum EvalSources {
    /// The sentence every benchmark shows after its source and licence.
    public static let shipLine = "Downloaded to this Mac on first use; One Roof does not ship it."
    public static let lockedLine = "Needs your Hugging Face account: accept the dataset's terms on Hugging Face, then sign in here."

    private static func hf(_ folder: String, _ id: String, _ licence: String, gated: Bool = false) -> EvalDataSource {
        EvalDataSource(folder: folder, origin: id, url: "https://huggingface.co/datasets/\(id)", licence: licence, gated: gated)
    }

    public static let table: [String: EvalDataSource] = {
        let all: [EvalDataSource] = [
            hf("mmlu_pro", "TIGER-Lab/MMLU-Pro", "MIT"),
            EvalDataSource(folder: "gpqa", origin: "OpenAI simple-evals copy of GPQA Diamond",
                           url: "https://github.com/openai/simple-evals", licence: "CC BY 4.0"),
            hf("hle", "cais/hle", "MIT", gated: true),
            EvalDataSource(folder: "simpleqa", origin: "OpenAI simple-evals", url: "https://github.com/openai/simple-evals", licence: "MIT"),
            hf("truthfulqa", "truthfulqa/truthful_qa", "Apache-2.0"),
            hf("gsm8k", "openai/gsm8k", "MIT"),
            hf("math", "DigitalLearningGmbH/MATH-lighteval", "MIT"),
            hf("aime2025", "math-ai/aime25", "Apache-2.0"),
            hf("arc", "allenai/ai2_arc", "CC BY-SA 4.0"),
            hf("bbh", "Joschka/big_bench_hard", "MIT"),
            hf("musr", "TAUR-Lab/MuSR", "CC BY 4.0"),
            hf("ifeval", "google/IFEval", "Apache-2.0"),
            hf("humaneval", "openai/openai_humaneval", "MIT"),
            hf("mbpp", "google-research-datasets/mbpp", "CC BY 4.0"),
            hf("bigcodebench", "bigcode/bigcodebench", "Apache-2.0"),
            hf("livecodebench_pro", "QAQAQAQAQ/LiveCodeBench-Pro", "Apache-2.0", gated: true),
            hf("swe_bench", "princeton-nlp/SWE-bench_Verified", "not stated on the dataset card (SWE-bench code: MIT)"),
            EvalDataSource(folder: "bfcl", origin: "Gorilla repository (Berkeley Function Calling Leaderboard)",
                           url: "https://github.com/ShishirPatil/gorilla", licence: "Apache-2.0"),
            EvalDataSource(folder: "tau2", origin: "Sierra tau2-bench", url: "https://github.com/sierra-research/tau2-bench", licence: "MIT"),
            hf("gaia", "gaia-benchmark/GAIA", "not stated on the dataset card", gated: true),
            hf("niah", "opencompass/NeedleBench", "MIT"),
            hf("xstest", "walledai/XSTest", "CC BY 4.0", gated: true),
            EvalDataSource(folder: "strong_reject", origin: "StrongREJECT repository", url: "https://github.com/alexandrasouly/strongreject",
                           licence: "MIT"),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.folder, $0) })
    }()

    /// The four sets that needed manual approval on Hugging Face, plus any other the table marks gated.
    public static var gatedFolders: [String] { table.values.filter(\.gated).map(\.folder).sorted() }

    /// A benchmark's source. Unknown benchmarks fall back to what the engine's anatomy says (dataset id, gated); your
    /// own sets come from your repo and need no disclosure of a third party.
    public static func source(folder: String, dataset: String? = nil, gated: Bool = false) -> EvalDataSource? {
        if let s = table[folder] { return gated && !s.gated ? EvalDataSource(folder: s.folder, origin: s.origin, url: s.url, licence: s.licence, gated: true) : s }
        if folder.hasPrefix("own-") { return nil }
        if let d = dataset, !d.isEmpty { return hf(folder, d, "see the dataset card", gated: gated) }
        return EvalDataSource(folder: folder, origin: "the benchmark's maker (inspect_evals)",
                              url: "https://github.com/UKGovernmentBEIS/inspect_evals", licence: "see the benchmark's source", gated: gated)
    }

    /// "Data: cais/hle (Hugging Face) · Licence MIT · Downloaded to this Mac on first use; One Roof does not ship it."
    public static func line(_ s: EvalDataSource) -> String {
        "Data: \(s.origin)\(s.isHuggingFace ? " (Hugging Face)" : "") · Licence \(s.licence) · \(shipLine)"
    }
}

/// LAB-2117 · whether a gated benchmark may be browsed, downloaded or run on this Mac.
public enum EvalGate {
    public enum Status: Equatable, Sendable {
        /// Not gated: open to everyone.
        case open
        /// Gated, and no Hugging Face account is signed in here.
        case needsSignIn
        /// Signed in, but the user has not said they accepted this dataset's terms on Hugging Face.
        case needsTerms
        /// Signed in and terms accepted: works (Hugging Face itself still refuses if the terms were not really accepted).
        case unlocked

        public var locked: Bool { self == .needsSignIn || self == .needsTerms }
        public var label: String {
            switch self {
            case .open: return "Open"
            case .needsSignIn: return "Locked · sign in"
            case .needsTerms: return "Locked · accept the terms"
            case .unlocked: return "Accepted"
            }
        }
    }

    public static func status(_ s: EvalDataSource?, signedIn: Bool, accepted: Set<String>) -> Status {
        guard let s, s.gated else { return .open }
        if !signedIn { return .needsSignIn }
        return accepted.contains(s.folder) ? .unlocked : .needsTerms
    }

    /// The reason Start is refused when the plan holds a locked benchmark (nil when every one is open or unlocked).
    public static func startReason(tasks: [String], folderOf: (String) -> String?, signedIn: Bool, accepted: Set<String>) -> String? {
        for t in tasks {
            guard let f = folderOf(t), let s = EvalSources.table[f] else { continue }
            let st = status(s, signedIn: signedIn, accepted: accepted)
            if st == .needsSignIn { return "\(EvalBenchmark.taskLabel(t)) is gated: sign in with your Hugging Face account (Settings › Evals)" }
            if st == .needsTerms { return "\(EvalBenchmark.taskLabel(t)) is gated: accept its terms on Hugging Face, then tick it in Settings › Evals" }
        }
        return nil
    }

    /// What the engine is told (ONEROOF_HF_ACCEPTED): the accepted gated folders, comma-separated and sorted.
    public static func acceptedEnv(_ accepted: Set<String>) -> String { accepted.sorted().joined(separator: ",") }

    /// A Hugging Face access token's shape (hf_ + letters and digits); used to refuse pasting something else.
    public static func looksLikeToken(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("hf_") && t.count >= 20 && t.count <= 200 && t.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
