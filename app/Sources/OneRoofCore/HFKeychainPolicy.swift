import Foundation

/// LAB-2246 · LAB-2251 · whether this copy of One Roof may touch the login Keychain for the Hugging Face token.
///
/// The owner kept seeing macOS's Keychain password prompt from test, candidate and A/B copies of the app. The rule now:
///   1. `ONEROOF_NO_KEYCHAIN=1` (every test and harness launcher sets it): no Keychain call at all, not even an
///      attribute query. Hugging Face is locked for that run.
///   2. Only a Developer-ID-signed app running from `/Applications/` may read the token, quietly or with the prompt
///      (the Test button). Any other copy (a dev build, a scratch bundle, a test copy, a candidate in a release folder)
///      treats Hugging Face as locked and says so; it makes no Keychain call either.
///   3. Unchanged: no read at launch, the token only for gated actions, the Test button may prompt.
///
/// Older builds used as A/B baselines (2.0.5 and before) don't know `ONEROOF_NO_KEYCHAIN`. The harness launches them with
/// `ONEROOF_FRESH_PROFILE=1` (run-app.sh, perf-check.sh), which points them at a separate item
/// ("huggingface-token.fresh") that does not exist: their launch-time attribute query finds nothing and cannot prompt.
public enum HFKeychainPolicy {
    public static let envKey = "ONEROOF_NO_KEYCHAIN"

    public enum Decision: Equatable, Sendable {
        case allowed
        /// ONEROOF_NO_KEYCHAIN=1: a test or harness run.
        case disabledForTests
        /// Not the released app in /Applications (unsigned, ad hoc, or another folder).
        case untrustedCopy
    }

    /// True when the environment turns the Keychain off for this run.
    public static func disabled(env: [String: String]) -> Bool {
        let v = (env[envKey] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return ["1", "true", "yes"].contains(v)
    }

    /// The app's bundle is directly in /Applications (not a copy elsewhere, not inside another folder there).
    public static func inApplications(_ bundlePath: String) -> Bool {
        let p = (bundlePath as NSString).standardizingPath
        guard p.hasPrefix("/Applications/"), p.hasSuffix(".app") else { return false }
        return !p.dropFirst("/Applications/".count).dropLast(4).contains("/")
    }

    /// The decision for any Keychain call (read, attribute query, save, delete). `trusted` = signed with a Developer ID
    /// team. `prompt` (the Test button) never widens it: a copy that may not read quietly may not prompt either.
    public static func decision(env: [String: String], bundlePath: String, trusted: Bool, prompt: Bool = false) -> Decision {
        if disabled(env: env) { return .disabledForTests }
        guard trusted, inApplications(bundlePath) else { return .untrustedCopy }
        return .allowed
    }

    /// May this copy read the token (quietly, or with the prompt when `prompt`)?
    public static func mayRead(env: [String: String], bundlePath: String, trusted: Bool, prompt: Bool) -> Bool {
        decision(env: env, bundlePath: bundlePath, trusted: trusted, prompt: prompt) == .allowed
    }

    /// What the settings pane and the lock card say when this copy may not use the token.
    public static func lockedLine(_ d: Decision) -> String? {
        switch d {
        case .allowed: return nil
        case .disabledForTests:
            return "Hugging Face is locked in this test run (ONEROOF_NO_KEYCHAIN=1): One Roof makes no Keychain call."
        case .untrustedCopy:
            return "Hugging Face is locked in this copy of One Roof: only the released app in /Applications reads the token from the Keychain."
        }
    }
}
