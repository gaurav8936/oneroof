import Foundation

// LAB-1305 (1.9.5) · Learn › a card's Listen tab shows the card's own page from the Agentic Engineering deck (the same
// HTML the repository and the other sites show: its diagram, its sections menu, its step pills, its own narration player),
// loaded in place from the packaged deck. One Roof draws nothing of its own there; the native scene view is only the
// fallback for a card without a page. This file holds the testable parts: which page (or none), the folder WebKit may
// read, the media bridge that keeps One Roof's player and the page's player from talking over each other, and the
// card a clicked link inside the page points to.

public enum LearnCardPage {
    /// The page to load and the folder WebKit may read (the deck root, so the page's `<slug>_audio/` clips and the
    /// field-manual pages it links to load in place).
    public struct Source: Equatable, Sendable {
        public var page: String
        public var readRoot: String
        public var url: URL { URL(fileURLWithPath: page) }
        public var readAccess: URL { URL(fileURLWithPath: readRoot, isDirectory: true) }
    }

    /// The card's own page, or nil when the deck has no HTML page for it (the station then draws the native fallback).
    public static func source(_ slug: String, in deck: LearnDeck,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Source? {
        guard let c = deck.cards[slug], c.html.lowercased().hasSuffix(".html") else { return nil }
        let page = deck.htmlPath(slug)
        guard exists(page) else { return nil }
        return Source(page: page, readRoot: deck.root)
    }

    /// The card whose page a clicked local link opens (another card's page), if it is one of the deck's.
    public static func linkedCard(_ path: String, in deck: LearnDeck) -> String? {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        let slug = ((std as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let c = deck.cards[slug] else { return nil }
        let own = URL(fileURLWithPath: deck.root + "/" + c.html).standardizedFileURL.path
        return own == std ? slug : nil
    }

    /// The script message handler the bridge posts to.
    public static let handler = "oneroofMedia"

    /// Injected at document start: tells One Roof whenever the page starts its own narration (an audio clip through
    /// HTMLMediaElement.play, or the device voice through speechSynthesis.speak), and gives One Roof `__oneroofPause()`,
    /// which stops the page's narration the way the page's own ❚❚ button does (and silences any clip or voice left).
    /// Posts "ready" once the page has loaded. `muted` (self-tests only) plays the page's clips silently.
    public static var bridgeScript: String { bridgeScript(muted: false) }
    public static func bridgeScript(muted: Bool) -> String {
        """
        (function(){
          var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handler);
          if (!h || window.__oneroofMedia) return;
          var media = window.__oneroofMedia = [];
          function tell(kind){ try { h.postMessage(kind); } catch (e) {} }
          var play = HTMLMediaElement.prototype.play;
          HTMLMediaElement.prototype.play = function(){
            if (media.indexOf(this) < 0) media.push(this);
            \(muted ? "this.muted = true;" : "")
            tell("play");
            return play.apply(this, arguments);
          };
          if (window.speechSynthesis && window.speechSynthesis.speak) {
            var speak = window.speechSynthesis.speak.bind(window.speechSynthesis);
            window.speechSynthesis.speak = function(u){ tell("speak"); return speak(u); };
          }
          window.__oneroofPause = function(){
            var b = document.getElementById("play");
            if (b && /Pause/.test(b.textContent || "")) b.click();
            media.forEach(function(m){ try { m.pause(); } catch (e) {} });
            if (window.speechSynthesis) { try { window.speechSynthesis.cancel(); } catch (e) {} }
          };
          window.addEventListener("load", function(){ tell("ready"); });
        })();
        """
    }

    /// Run when One Roof's own player starts: the page goes quiet.
    public static let pauseScript = "window.__oneroofPause && window.__oneroofPause();"

    /// While One Roof's player plays this card, the page shows the scene being heard, through the page's own scene
    /// dots (a dot click with the page paused shows the scene without starting the page's voice). Only when the
    /// page has exactly one dot per One Roof track, so a page whose scenes and clips differ is left alone.
    public static func showSceneScript(_ index: Int, tracks: Int) -> String {
        "(function(){ var d = document.querySelectorAll('#dots .dot'); if (d.length === \(tracks) && d[\(index)]) d[\(index)].click(); })();"
    }
}
