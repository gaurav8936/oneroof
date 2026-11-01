import Foundation

/// LAB-2116 · every narrated player says plainly that the voice is AI-generated. OpenAI's text-to-speech guide (checked
/// 2026-11-01, developers.openai.com/api/docs/guides/text-to-speech): "Our usage policies require you to provide a clear
/// disclosure to end users that the TTS voice they are hearing is AI-generated and not a human voice."
/// `tools/release-check.sh` fails if a narrated player or THIRD-PARTY-NOTICES.md lacks the line.
public enum Narration {
    /// Shown on every player (Learn Radio, card and paper pages, the player bar, Evals › How to).
    public static let disclosure = "Narration: AI-generated voice (OpenAI text-to-speech)."
    /// The longer form, for help text and VoiceOver.
    public static let detail = "The narration is an AI-generated voice made with OpenAI text-to-speech, not a human voice."
    public static let policyURL = "https://openai.com/policies/usage-policies"
}
