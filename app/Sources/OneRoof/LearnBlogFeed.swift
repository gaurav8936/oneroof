import Foundation
import OneRoofCore

/// LAB-1251 · the author's posts from the blog hub (BlogHub), for Learn › Writing, the post reader, band posts and the
/// broadcast schedule. Learn reads the cache (`BlogHub.cacheDir`) at once; this refreshes it in the background when
/// Learn opens (at most every ten minutes unless asked), and says whether the hub answered so the empty states can be
/// honest ("loading", "offline with no saved copy", "the blog has no posts").
@MainActor
final class LearnBlogFeed: ObservableObject {
    static let shared = LearnBlogFeed()

    enum State: Equatable {
        /// Not asked yet this run.
        case idle
        case loading
        /// The hub answered with this many posts.
        case reached(Int)
        /// The hub could not be read (the reason, short).
        case offline(String)
    }

    @Published private(set) var state: State = .idle
    /// Bumped when a sync wrote the cache: Learn reads it again.
    @Published private(set) var revision = 0
    private var running = false
    private var last: Date?

    /// When the saved copy was last filled from the hub (nil: never on this Mac).
    var savedAt: Date? { BlogHub.lastSync() }

    func refresh(force: Bool = false) {
        guard !running else { return }
        if !force, let last, Date().timeIntervalSince(last) < 600 { return }
        running = true
        if case .reached = state {} else { state = .loading }
        Task.detached(priority: .utility) {
            let r = await BlogHub.sync()
            await MainActor.run {
                let feed = LearnBlogFeed.shared
                feed.running = false
                feed.last = Date()
                if r.reached {
                    feed.state = .reached(r.posts)
                    feed.revision += 1
                } else {
                    feed.state = .offline(r.error ?? "no answer")
                }
            }
        }
    }
}
