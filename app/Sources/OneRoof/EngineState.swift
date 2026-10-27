import Combine
import OneRoofCore

/// LAB-1338 · what the engines publish while agents work: captions, the feed, step chapters and subagents. Split out of
/// AppModel so a caption or a subagent tick re-renders only the views that show one (they observe this store), not
/// every view observing the model. AppModel keeps `captions`, `feed`, `chapters` and `subagents` as pass-throughs.
final class EngineState: ObservableObject {
    static let shared = EngineState()
    @Published var captions: [String: LiveCaption] = [:]
    @Published var subagents: [String: [Subagent]] = [:]
    @Published var chapters: [String: [Chapter]] = [:]
    @Published var feed: [FeedEntry] = []
}
