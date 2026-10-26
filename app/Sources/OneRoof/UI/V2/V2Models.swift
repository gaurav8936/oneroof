import SwiftUI
import OneRoofCore

// Plain value types the v2 views draw from. V2Adapters.swift fills them from AppModel,
// so the views compile and preview on their own.

struct V2Seat: Identifiable, Hashable { var id: String { name }; var name: String; var used: Double; var label: String; var badge: Color; var badgeText: Color; var off: Bool }

struct V2SessionRow: Identifiable, Hashable {
    var id: String
    var badge: String          // C1, C2, CX, KM, GM, >_
    var badgeColor: Color
    var title: String
    var statusLine: String
    var status: SessionStatus
    var meta: String           // repo · ticket
    var age: String
    var exited: Bool { status == .exited }
    var slot: Int? = nil       // Grid tile number
}

struct V2Step: Identifiable, Hashable { var id: Int; var title: String; var done: Bool; var calls: Int; var age: String; var summary: String }

struct V2SessionSummary {
    var asked: String; var askedAt: String; var rightNow: String
    var steps: [V2Step]; var agent: String; var ticket: String?
}

struct V2Dock { var seats: [V2Seat]; var roofd: String; var foundationsIssues: Int; var machine: String; var needsYou: Int; var tonight: Int }

struct V2WindowRef: Identifiable, Hashable { var id: String; var name: String; var color: Color; var count: Int; var state: String }

enum V2Badge {
    static func color(_ agent: AgentKind, account: Int) -> (Color, Color, String) {
        switch agent {
        case .claude: return account == 2 ? (Color(.systemYellow), .black, "C2") : (Color(.systemOrange), .white, "C1")
        case .codex: return (Color(.systemGreen), .white, "CX")
        case .kimi: return (Color(.systemPurple), .white, "KM")
        case .gemini: return (Color(.systemIndigo), .white, "GM")
        case .agy: return (Color(.systemTeal), .white, "AG")
        case .shell: return (Color(.systemGray), .black, ">_")
        }
    }
}

extension V2SessionRow {
    static let samples: [V2SessionRow] = [
        .init(id: "1", badge: "C1", badgeColor: Color(.systemOrange), title: "Docs site", statusLine: "Working · step 3 of 4", status: .running, meta: "docs-site · DOC-12", age: "0s"),
        .init(id: "2", badge: "CX", badgeColor: Color(.systemGreen), title: "QA pass", statusLine: "Ready for you", status: .done, meta: "workspace root · APP-40", age: "3s"),
        .init(id: "3", badge: "C1", badgeColor: Color(.systemOrange), title: "App · Bug fixes", statusLine: "Idle · 3 subagents done", status: .idle, meta: "apps/main", age: "10s"),
        .init(id: "4", badge: "C2", badgeColor: Color(.systemYellow), title: "Reference check", statusLine: "Idle <1m", status: .idle, meta: "docs", age: "10s"),
        .init(id: "5", badge: ">_", badgeColor: Color(.systemGray), title: "Terminals · 2", statusLine: "Idle 6m", status: .idle, meta: "workspace root", age: "8m"),
        .init(id: "6", badge: "C1", badgeColor: Color(.systemOrange), title: "Blog post", statusLine: "Exited", status: .exited, meta: "WEB-7", age: "1d"),
    ]
}
extension V2Dock {
    static let sample = V2Dock(seats: [
        .init(name: "C1", used: 0.09, label: "9% · 5h", badge: Color(.systemOrange), badgeText: .white, off: false),
        .init(name: "C2", used: 0.05, label: "5% · 5h", badge: Color(.systemYellow), badgeText: .black, off: false),
        .init(name: "CX", used: 0.19, label: "19% · week", badge: Color(.systemGreen), badgeText: .white, off: false),
        .init(name: "KM", used: 0, label: "off", badge: Color(.systemPurple), badgeText: .white, off: true),
        .init(name: "GM", used: 0, label: "off", badge: Color(.systemIndigo), badgeText: .white, off: true)],
        roofd: "roofd 0.5.2.7 · 4 agents", foundationsIssues: 1, machine: "Mac · 2.8 GB · 62% CPU", needsYou: 0, tonight: 0)
}
