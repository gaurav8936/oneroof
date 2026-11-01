import Foundation

// LAB-1894 · the classic Learn screens' self-test hooks, moved to the shared page when those screens were removed, so the
// existing captures (scripts/ui2-screens.tsv A12.*), journeys and perf scenarios keep working. Pure: the app runs what
// these return in the page (LearnSharedController). Variables:
//
//   ONEROOF_SELFTEST_LEARNMODE   radio · band[:id[:track]] · card[:slug[:tab]] · writing · post[:slug] · path[:id] · library | map ·
//                                search:<text> · folder[:<path from the deck root>] · radiokey:<band> · radiochip:<band>:<track>
//   ONEROOF_SELFTEST_RAILFOLDED=1           the card screen's side panel folded (the page's own setting, this run only)
//   ONEROOF_SELFTEST_AUTOADVANCE=0          Auto-next off for this run
//   ONEROOF_SELFTEST_CARDENDED=<s> | finish@<s>   the first card page says it ended (or plays to its end) s seconds after it loaded
//   ONEROOF_SELFTEST_PAGECLICK=<id>[@<s>],…       click elements of the first card page s seconds after it loaded
//   ONEROOF_SELFTEST_PAGEJS=<s>@<script>         run a script in the first card page s seconds after it loaded
public enum LearnSharedSelfTest {
    public struct Plan: Equatable, Sendable {
        /// Where the page opens.
        public var hash: String
        /// Scripts for the page, each that many seconds after it mounted.
        public var scripts: [Step]
        public init(hash: String, scripts: [Step] = []) { self.hash = hash; self.scripts = scripts }
    }
    public struct Step: Equatable, Sendable {
        public var after: Double
        public var js: String
        public init(_ after: Double, _ js: String) { self.after = after; self.js = js }
    }

    /// ONEROOF_SELFTEST_LEARNMODE → the shared page's screen (and what to do there).
    public static func mode(_ spec: String) -> Plan {
        let f = spec.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let a = f.count > 1 ? f[1] : "", b = f.count > 2 ? f[2] : ""
        let e = LearnShared.enc
        switch f.first ?? "radio" {
        case "band": return Plan(hash: a.isEmpty ? "#ae/radio" : "#ae/band/\(e(a))" + (b.isEmpty ? "" : "/\(e(b))"))
        case "card":
            let tab = ["transcript", "skill"].contains(b) ? "/" + b : ""
            return Plan(hash: "#ae/card/\(e(a.isEmpty ? "loops-first" : a))" + tab)
        case "writing": return Plan(hash: "#ae/writing")
        case "post": return Plan(hash: a.isEmpty ? "#ae/writing" : "#ae/post/\(e(a))")
        case "path": return Plan(hash: "#ae/path/\(e(a.isEmpty ? "vibe-to-prod" : a))")
        case "library", "map": return Plan(hash: "#ae/cards")
        case "search":
            let q = f.dropFirst().joined(separator: ":")
            return Plan(hash: "#ae/cards", scripts: [Step(1, "oneroofLearnSearch(\(js(q)))")])
        case "folder":
            let rel = deckPath(f.dropFirst().joined(separator: ":"))
            return Plan(hash: "#ae/cards/folder", scripts: rel.isEmpty ? [] : [Step(1, selectFolder(rel))])
        case "radiokey": return Plan(hash: "#ae/radio", scripts: [Step(3.5, "location.hash = \(js("#ae/band/" + e(a.isEmpty ? "context" : a)))")])
        case "radiochip":
            return Plan(hash: "#ae/radio", scripts: [Step(3.5, "location.hash = \(js("#ae/band/\(e(a.isEmpty ? "context" : a))/\(e(b.isEmpty ? "vault" : b))"))")])
        default: return Plan(hash: "#ae/radio")
        }
    }

    /// The classic screens' By folder paths were under the deck's `skills/`; the shared page shows its `content/` folder, where
    /// the same card folders are (`content/cards/<track>/<card>`).
    public static func deckPath(_ rel: String) -> String {
        rel.hasPrefix("skills/") ? "content/cards/" + rel.dropFirst("skills/".count) : rel
    }

    /// Opens By folder down to `rel` and selects it, as a person clicks: each closed folder above it, then it (the rows load from
    /// disk as they open, so it waits for each).
    public static func selectFolder(_ rel: String) -> String {
        """
        (function(target){var parts=target.split('/'),chain=[],t0=Date.now(),clicked={};
        for(var i=2;i<=parts.length;i++)chain.push(parts.slice(0,i).join('/'));
        function row(id){return document.querySelector('.ae-tr[data-id="'+id.replace(/"/g,'')+'"]');}
        function step(){if(Date.now()-t0>20000)return;
          for(var k=0;k<chain.length;k++){if(!row(chain[k])){var up=k>0?row(chain[k-1]):null;if(up&&!clicked[chain[k-1]]){clicked[chain[k-1]]=1;up.click();}return setTimeout(step,250);}}
          var r=row(target);if(r&&!clicked[target]){clicked[target]=1;r.click();}}
        step();})(\(js(rel)));
        """
    }

    /// A script for the first card page in the Listen frame, `after` seconds once it has loaded (its scene dots are drawn).
    public static func inCardPage(after: Double, _ script: String) -> String {
        """
        (function(){var t0=Date.now();function go(){var f=document.querySelector('.ae-stage iframe');var d=null;try{d=f&&f.contentDocument;}catch(e){}
          if(!d||d.readyState!=='complete'||!d.getElementById('dots')){if(Date.now()-t0<30000)setTimeout(go,200);return;}
          setTimeout(function(){try{f.contentWindow.eval(\(js(script)));}catch(e){}},\(Int(after * 1000)));}go();})();
        """
    }

    /// CARDENDED / PAGECLICK / PAGEJS → scripts run in the first card page (empty when none is set).
    public static func cardPageScripts(_ env: [String: String]) -> [String] {
        var out: [String] = []
        if let s = env["ONEROOF_SELFTEST_CARDENDED"] {
            // "finish@<s>": the page's own end (its test hook plays the last scene and steps past it), not a posted message.
            let real = s.hasPrefix("finish@")
            let at = Double(real ? String(s.dropFirst(7)) : s) ?? 1
            out.append(inCardPage(after: at, real ? "window.__AE__ && window.__AE__.finish && window.__AE__.finish();"
                                                   : "window.parent.postMessage({ type: 'ae-card-ended' }, '*');"))
        }
        if let pj = env["ONEROOF_SELFTEST_PAGEJS"], let at = pj.firstIndex(of: "@") {
            out.append(inCardPage(after: Double(pj[..<at]) ?? 1, String(pj[pj.index(after: at)...])))
        }
        for one in (env["ONEROOF_SELFTEST_PAGECLICK"] ?? "").split(separator: ",") where !one.isEmpty {
            let f = one.split(separator: "@").map(String.init)
            let id = (f.first ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            out.append(inCardPage(after: f.count > 1 ? Double(f[1]) ?? 1 : 1, "var e = document.getElementById('\(id)'); if (e) e.click();"))
        }
        return out
    }

    /// Run before the page's own scripts: RAILFOLDED=1 folds the card screen's side panel (the page's storage; a self-test's
    /// web storage is thrown away when it quits).
    public static func startScript(_ env: [String: String]) -> String? {
        env["ONEROOF_SELFTEST_RAILFOLDED"] == "1" ? "try { localStorage.setItem('ggae.sidePanel', 'hidden'); } catch (e) {}" : nil
    }

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }
}
