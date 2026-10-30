import Foundation

// LAB-1621 · Learn › a card played to its end rolls over to the next card (sit-back listening). The card page tells
// the host it ended (the deck's card-end contract, decision 20261029_01 in the deck repository): in WKWebView it posts
// `{type: 'ended', card}` to `window.webkit.messageHandlers.aeCard`. One Roof then counts down three seconds
// ("Next: <title> in 3…", Stay cancels; Esc and pressing play or pause cancel too) and opens the next card with
// `?autoplay=1`, posting `{type: 'ae-play'}` as a fallback once it has loaded. Speed, voice and CC live in the page's
// own storage (one origin for every card), so they carry over by themselves. This file holds the testable parts.

public enum LearnRollover {
    /// The script message handler the card page posts its end to (the contract's name).
    public static let handler = "aeCard"

    /// Seconds the countdown runs before the next card opens.
    public static let seconds = 3

    /// The query the next card's page is opened with, so it starts playing by itself.
    public static let autoplayQuery = "autoplay=1"

    /// The card that ended, from an `aeCard` message: `{type: 'ended', card: '<slug>'}`. A message without a card counts
    /// as the shown card's end (`fallback`); any other type is not an end.
    public static func endedCard(_ body: Any, fallback: String) -> String? {
        if let d = body as? [String: Any] {
            guard (d["type"] as? String) == "ended" else { return nil }
            if let c = d["card"] as? String, !c.isEmpty { return c }
            return fallback
        }
        if let s = body as? String, s == "ended" { return fallback }
        return nil
    }

    /// The card to roll over to after `slug`: the next on its band ("Next on the <band> band", the band's dial order);
    /// at the end of a band, the next band's first start-here card. Nil after the last card of the last band (the run
    /// stops there rather than starting the deck again) or for a card the deck does not know.
    public static func next(after slug: String, in deck: LearnDeck) -> String? {
        guard deck.cards[slug] != nil else { return nil }
        let band = deck.band(of: slug)
        let list = deck.lists[band.id] ?? []
        if let at = list.firstIndex(of: slug), at + 1 < list.count { return list[at + 1] }
        guard let bi = deck.bands.firstIndex(where: { $0.id == band.id }) else { return nil }
        for b in deck.bands.dropFirst(bi + 1) {
            if let k = b.key.first(where: { deck.cards[$0] != nil && $0 != slug }) { return k }
            if let k = (deck.lists[b.id] ?? []).first(where: { $0 != slug }) { return k }
        }
        return nil
    }

    /// The card before `slug` in the same order (LAB-1629 ⏮): the previous on its band; at the start of a band, the
    /// previous band's last card. Nil before the first card of the first band.
    public static func previous(before slug: String, in deck: LearnDeck) -> String? {
        guard deck.cards[slug] != nil else { return nil }
        let band = deck.band(of: slug)
        let list = deck.lists[band.id] ?? []
        if let at = list.firstIndex(of: slug), at > 0 { return list[at - 1] }
        guard let bi = deck.bands.firstIndex(where: { $0.id == band.id }) else { return nil }
        for b in deck.bands.prefix(bi).reversed() {
            if let k = (deck.lists[b.id] ?? []).last(where: { $0 != slug }) { return k }
        }
        return nil
    }

    /// LAB-1629 · what the card page's player bar asks the host to do: `{type: 'ae-nav', to: 'prev-card' | 'next-card' |
    /// 'band', card, playing?}`.
    public enum Nav: String, Equatable, Sendable { case prevCard = "prev-card", nextCard = "next-card", band }
    public struct NavRequest: Equatable, Sendable {
        public var to: Nav
        public var card: String
        /// The page said whether it was playing (nil: it did not say; the host asks the page).
        public var playing: Bool?
    }

    /// The navigation an `aeCard` message asks for, if it is one (`fallback` = the shown card when it names none).
    public static func navRequest(_ body: Any, fallback: String) -> NavRequest? {
        guard let d = body as? [String: Any], (d["type"] as? String) == "ae-nav",
              let to = (d["to"] as? String).flatMap(Nav.init(rawValue:)) else { return nil }
        let card = (d["card"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let playing = (d["playing"] as? Bool) ?? (d["playing"] as? NSNumber)?.boolValue
        return NavRequest(to: to, card: card, playing: playing)
    }

    /// Whether the page's own player is playing (its ▶/❚❚ button says Pause): evaluated to a Bool.
    public static let isPlayingScript = "(function(){ var b = document.getElementById('play'); return !!(b && /Pause/.test(b.textContent || '')); })();"

    /// The countdown line: "Next: <title> in 3…".
    public static func label(title: String, left: Int) -> String { "Next: \(title) in \(max(0, left))…" }

    /// The page's file URL with `?autoplay=1` (or as is when `autoplay` is false).
    public static func url(_ page: String, autoplay: Bool) -> URL {
        let file = URL(fileURLWithPath: page)
        guard autoplay, var c = URLComponents(url: file, resolvingAgainstBaseURL: false) else { return file }
        c.percentEncodedQuery = autoplayQuery
        return c.url ?? file
    }

    /// Run once the autoplayed page has loaded: if it is not playing yet (a page without `?autoplay=1` support), post
    /// `{type: 'ae-play'}` (the contract's fallback); if that did not start it either, press the page's own
    /// "Play from the start" (a deck built before the contract).
    public static let playScript = """
    (function(){
      function on(){ var b = document.getElementById("play"); return !!(b && /Pause/.test(b.textContent || "")); }
      if (on()) return;
      try { window.postMessage({type: "ae-play"}, "*"); } catch (e) {}
      setTimeout(function(){ if (on()) return; var a = document.getElementById("playAll"); if (a) a.click(); }, 500);
    })();
    """

    /// Injected at document start next to the media bridge: Esc in the page tells One Roof (it cancels a countdown), as
    /// the page's own keys go to the page while it has the keyboard.
    public static func escapeScript(media: String) -> String {
        """
        (function(){
          var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(media);
          if (!h) return;
          document.addEventListener("keydown", function(e){ if (e.key === "Escape") { try { h.postMessage("escape"); } catch (x) {} } }, true);
        })();
        """
    }

    /// Self-tests (ONEROOF_SELFTEST_CARDENDED): the page posting its end, as a card played to its end does.
    public static func endedScript(card: String) -> String {
        let safe = card.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "(function(){ var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handler); if (h) h.postMessage({type: 'ended', card: '\(safe)'}); })();"
    }
}
