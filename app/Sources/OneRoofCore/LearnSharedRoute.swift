import Foundation

// LAB-1837 · a way into Learn (a link, Search, the Plan panel, the player) opens the shared page at the same place the classic
// screens would: the embed keeps its screen in the URL hash (#ae/card/<slug>, #ae/band/<id>[/<track>], #ae/radio).
public extension LearnShared {
    /// The embed's screen for a Learn target (`#ae/card/<slug>`, `#ae/band/<id>[/<track>]`, `#ae/radio`); nil for anything
    /// the page does not show (One Roof Help, an extra-folder page).
    static func hash(_ route: LearnTargetRoute) -> String? {
        switch route {
        case .card(let s): return "#ae/card/\(enc(s))"
        case .band(let id, let track): return "#ae/band/\(enc(id))" + (track.map { "/\(enc($0))" } ?? "")
        case .radio: return "#ae/radio"
        case .help, .none: return nil
        }
    }

}
