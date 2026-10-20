import Foundation
import OneRoofCore

/// What a row, card or pane shows as the session's one-line caption (COMPONENTS CaptionLine).
struct LiveCaption: Equatable {
    enum Tone { case normal, needs, now }
    var text: String
    var tone: Tone = .normal
    var step: Int?
    var steps: Int?
    /// "Right now …": the single action in progress.
    var now: String?
    /// "caption by on-device model" / "from the terminal" (tooltip).
    var source: String = "from the terminal"
}

extension AppModel {
    /// The caption for a session: the caption engine's latest, else a status line (never invented output).
    func caption(for item: BoardItem) -> LiveCaption {
        // A session that has ended says so, whatever its last live caption was ("Idle <1m" under Exited before).
        if item.status == .exited { return LiveCaption(text: "Exited") }
        if let c = captions[item.id] { return c }
        let s = item.session
        switch item.status {
        case .needsYou: return LiveCaption(text: "Needs you", tone: .needs)
        case .planned, .next:
            let first = s.objective.isEmpty ? s.openingMessage : s.objective
            return LiveCaption(text: first.isEmpty ? (item.status == .next ? "Up next" : "Planned") : String(first.prefix(90)))
        case .exited: return LiveCaption(text: "Exited")
        case .doNotUse: return LiveCaption(text: "Parked · do not use")
        default:
            if !s.agent.isAgent { return LiveCaption(text: (s.launchDirectory as NSString).abbreviatingWithTildeInPath) }
            return LiveCaption(text: item.title ?? "no caption yet")
        }
    }
}

extension AppModel {
    /// "2:00 AM" for a session scheduled tonight / nightly (S09 When, Schedules engine); nil otherwise.
    func scheduleLabel(_ item: BoardItem) -> String? { schedules[item.id] }
}
