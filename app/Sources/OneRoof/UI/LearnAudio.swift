import Foundation
import OneRoofCore

/// Playing deck cards through One Roof's player (CoursePlayer): Learn's shared page (Play in One Roof, Transcript › Play from
/// here, Radio), the player bar's ⏮ ⏭, the self-tests. Moved out of the classic Learn screens when they were removed (LAB-1894).
struct LearnAudio {
    let deck: LearnDeck
    let player: CoursePlayer
    /// Says why a card cannot play (a toast).
    var flash: (String) -> Void = { _ in }

    /// The card the player has loaded, if it is one of the deck's.
    var playingSlug: String? { player.pageId.flatMap { deck.slug(forPage: $0) } }

    /// Play `slug` from `scene`, then the cards in `then`, in order.
    func play(_ slug: String, scene: Int = 0, then rest: [String] = []) {
        guard let c = deck.cards[slug] else { return }
        let page = deck.htmlPath(slug), tracks = CourseAudio.tracks(page: page)
        guard !tracks.isEmpty else { flash("\(c.title) has no narration in this build"); return }
        let queue = rest.filter { $0 != slug }.compactMap { k -> CoursePlayer.QueuedPage? in
            guard let q = deck.cards[k] else { return nil }
            let p = deck.htmlPath(k)
            return CoursePlayer.QueuedPage(id: p, title: q.title, tracks: { CourseAudio.tracks(page: p) })
        }
        player.play(pageId: page, title: c.title, tracks: tracks, track: min(max(0, scene), tracks.count - 1), upNext: queue)
    }

    /// Play the card, or pause / resume it when it is the one loaded.
    func toggle(_ slug: String, scene: Int = 0, then rest: [String] = []) {
        if playingSlug == slug { player.toggle() } else { play(slug, scene: scene, then: rest) }
    }

    /// The rest of `slug`'s band, from it on.
    func bandFrom(_ slug: String) -> [String] {
        let l = deck.lists[deck.band(of: slug).id] ?? []
        return l.firstIndex(of: slug).map { Array(l[$0...]) } ?? [slug]
    }
}
