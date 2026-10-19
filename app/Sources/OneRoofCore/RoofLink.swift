import Foundation

/// `oneroof://` links, so a doc, a Slack message or a Knowledge page can point into One Roof.
/// A link can select, show or plan, never launch an agent or run anything (links can come from anywhere).
///
///   oneroof://session/<id | name | herdr agent>      select that session
///   oneroof://objective/<id | title>                 open the objective
///   oneroof://view/<terminals|launchpad|board|work|learn|review|search>[?q=text]
///   oneroof://open?path=<absolute path in ~/Projects>[&line=N]   show a file in the viewer
///   oneroof://new?agent=claude&repo=<path>&name=<name>[&message=<opening>]   plan a session (not started)
public enum RoofLink: Equatable, Sendable {
    case session(String)
    case objective(String)
    case view(String, query: String?)
    case file(String, line: Int?)
    case plan(agent: AgentKind, repo: String, name: String, message: String)

    public static let views: Set<String> = ["terminals", "launchpad", "board", "work", "learn", "review", "search"]

    public static func parse(_ url: URL) -> RoofLink? {
        guard url.scheme?.lowercased() == "oneroof", let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let q = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap { i in i.value.map { (i.name, $0) } } ?? [],
                           uniquingKeysWith: { a, _ in a })
        switch host {
        case "session":
            return parts.first.map { .session($0) }
        case "objective":
            return parts.first.map { .objective($0) }
        case "view":
            guard let v = parts.first?.lowercased(), views.contains(v) else { return nil }
            return .view(v, query: q["q"])
        case "open":
            guard let p = q["path"].map({ ($0 as NSString).expandingTildeInPath }), p.hasPrefix("/"),
                  Workspace.isInsideProjects((p as NSString).standardizingPath) else { return nil }
            return .file((p as NSString).standardizingPath, line: q["line"].flatMap(Int.init))
        case "new":
            let agent = q["agent"].flatMap { AgentKind(rawValue: $0.lowercased()) } ?? .claude
            let repo = q["repo"].map { (($0 as NSString).expandingTildeInPath as NSString).standardizingPath } ?? Workspace.projectsRoot
            guard Workspace.isInsideProjects(repo) else { return nil }
            return .plan(agent: agent, repo: repo, name: q["name"] ?? "Planned from a link", message: q["message"] ?? "")
        default:
            return nil
        }
    }

    /// The link that selects a session.
    public static func link(session id: String) -> String { "oneroof://session/" + id }
}
