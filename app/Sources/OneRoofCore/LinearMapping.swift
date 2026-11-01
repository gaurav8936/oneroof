import Foundation

/// LAB-2102 · how One Roof reads someone's Linear when their names differ from the recommended setup (Settings ›
/// Linear). One Roof speaks in six ticket states (Backlog · Todo · In Progress · In Review · Done · Canceled) and five
/// Type labels (Deliverable · Bug · Task · Spike · Decision); the mapping says what each is called in this workspace,
/// and which teams Projects leaves out. Only differences are stored. Kept next to the Linear key
/// (`~/.config/oneroof/linear-mapping.json`), never bundled: One Roof ships nobody's tracker data.
public struct LinearMapping: Codable, Equatable, Sendable {
    /// One Roof's state name → this workspace's (only the ones that differ).
    public var states: [String: String] = [:]
    /// WorkKind raw value (deliverable, defect, …) → this workspace's Type label (only the ones that differ).
    public var typeLabels: [String: String] = [:]
    /// Team keys Projects leaves out.
    public var hiddenTeams: [String] = []

    public init(states: [String: String] = [:], typeLabels: [String: String] = [:], hiddenTeams: [String] = []) {
        self.states = states; self.typeLabels = typeLabels; self.hiddenTeams = hiddenTeams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        states = try c.decodeIfPresent([String: String].self, forKey: .states) ?? [:]
        typeLabels = try c.decodeIfPresent([String: String].self, forKey: .typeLabels) ?? [:]
        hiddenTeams = try c.decodeIfPresent([String].self, forKey: .hiddenTeams) ?? []
    }

    public static let standard = LinearMapping()
    public var isStandard: Bool { self == .standard }

    /// One Roof's ticket states, in board order, with the Linear state type each belongs to.
    public static let canonicalStates = ["Backlog", "Todo", "In Progress", "In Review", "Done", "Canceled"]
    public static let stateType: [String: String] = ["Backlog": "backlog", "Todo": "unstarted", "In Progress": "started",
                                                     "In Review": "started", "Done": "completed", "Canceled": "canceled"]
    /// The Type labels One Roof reads, in the order Settings lists them.
    public static let typeKinds: [WorkKind] = [.deliverable, .defect, .chore, .spike, .decision]

    // MARK: States

    /// This workspace's name for one of One Roof's states (unchanged when not mapped or not one of them).
    public func stateName(_ canonical: String) -> String {
        guard let key = Self.canonicalStates.first(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) else { return canonical }
        let v = states[key]?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? key : v
    }

    /// The review state's name ("In Review" unless mapped): Projects works out In review from it.
    public var reviewState: String { stateName("In Review") }

    /// The team state to move a ticket to for one of One Roof's states: the mapped name exactly, then ignoring case,
    /// then the first state of the same type (In Progress never picks the review state, In Review prefers a started
    /// state with "review" in its name). nil when the team has nothing that fits.
    public func resolveState(_ canonical: String, in teamStates: [(id: String, name: String, type: String)]) -> (id: String, name: String)? {
        let want = stateName(canonical)
        if let s = teamStates.first(where: { $0.name == want }) { return (s.id, s.name) }
        if let s = teamStates.first(where: { $0.name.caseInsensitiveCompare(want) == .orderedSame }) { return (s.id, s.name) }
        guard let key = Self.canonicalStates.first(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }),
              let type = Self.stateType[key] else { return nil }
        let review = reviewState.lowercased()
        let sameType = teamStates.filter { $0.type == type }
        let pick: (id: String, name: String, type: String)?
        switch key {
        case "In Review":
            pick = sameType.first { $0.name.lowercased() == review } ?? sameType.first { $0.name.lowercased().contains("review") }
        case "In Progress":
            pick = sameType.first { $0.name.lowercased() != review && !$0.name.lowercased().contains("review") } ?? sameType.first
        default:
            pick = sameType.first
        }
        return pick.map { ($0.id, $0.name) }
    }

    /// The One Roof state a workspace state name stands for (the reverse of `stateName`), for the ticket menu's tick.
    public func canonical(forTeamState name: String) -> String? {
        Self.canonicalStates.first { stateName($0).caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Type labels

    /// The label names a kind is read from and created with: the mapped one first, then the standard names.
    public func labelNames(_ kind: WorkKind) -> [String] {
        var out: [String] = []
        if let v = typeLabels[kind.rawValue]?.trimmingCharacters(in: .whitespaces), !v.isEmpty { out.append(v) }
        for n in kind.labelNames where !out.contains(n) { out.append(n) }
        return out
    }

    /// The kind a label names (mapped names first; case ignored for mapped names).
    public func kind(fromLabel label: String) -> WorkKind? {
        for (raw, name) in typeLabels where name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(label) == .orderedSame {
            if let k = WorkKind(rawValue: raw) { return k }
        }
        return WorkKind.fromLabel(label)
    }

    /// The label the field shows for a kind (mapped, else the recommended one).
    public func labelName(_ kind: WorkKind) -> String { labelNames(kind).first ?? kind.rawValue }

    // MARK: Editing

    /// Set a state's name; the recommended name (or blank) removes the entry, so only differences are stored.
    public mutating func setState(_ canonical: String, to name: String) {
        let v = name.trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v == canonical { states[canonical] = nil } else { states[canonical] = v }
    }

    public mutating func setLabel(_ kind: WorkKind, to name: String) {
        let v = name.trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v == kind.labelNames.first { typeLabels[kind.rawValue] = nil } else { typeLabels[kind.rawValue] = v }
    }

    public mutating func setTeam(_ key: String, shown: Bool) {
        hiddenTeams.removeAll { $0 == key }
        if !shown { hiddenTeams.append(key); hiddenTeams.sort() }
    }

    /// Projects of the teams Projects shows.
    public func visible(_ projects: [LinearWorkstream]) -> [LinearWorkstream] {
        hiddenTeams.isEmpty ? projects : projects.filter { !hiddenTeams.contains($0.team) }
    }

    // MARK: Check against a team

    /// What does not fit a team as it is in Linear: a state One Roof moves tickets to that the team lacks (by name or by
    /// type), and Type labels it has none of. Empty = the mapping fits.
    public func problems(teamKey: String, states teamStates: [(id: String, name: String, type: String)], labels: [String]) -> [String] {
        var out: [String] = []
        for c in Self.canonicalStates where resolveState(c, in: teamStates) == nil {
            out.append("\(teamKey): no state for \(c) (looked for \"\(stateName(c))\")")
        }
        let have = Set(labels.map { $0.lowercased() })
        for k in Self.typeKinds where !labelNames(k).contains(where: { have.contains($0.lowercased()) }) {
            out.append("\(teamKey): no \(labelName(k)) label (Type: \(k.rawValue))")
        }
        return out
    }

    // MARK: File

    public static var path: String { NSHomeDirectory() + "/.config/oneroof/linear-mapping.json" }

    public static func load(path: String = LinearMapping.path) -> LinearMapping {
        guard let d = FileManager.default.contents(atPath: path), let m = try? JSONDecoder().decode(LinearMapping.self, from: d) else { return .standard }
        return m
    }

    public func save(to path: String = LinearMapping.path) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// LAB-2102 · the recommended Linear setup, as Settings › Linear explains it (plain words, one line each).
public enum LinearSetupGuide {
    public static let recommended: [(String, String)] = [
        ("Teams", "One team per area of work (for example Web, Mobile, Docs). Projects groups by team."),
        ("Projects", "One Linear project per body of work, named \"CODE · title\" (CODE like WEB-CHECKOUT). One Roof lists every project."),
        ("Milestones", "A project's milestones are its phases: the roadmap groups tickets by them, in Linear's order."),
        ("Project statuses", "Backlog · Planned · In progress · Completed · Canceled. In review is worked out: a started project whose open tickets are all in review."),
        ("Ticket statuses", "Backlog · Todo · In Progress · In Review · Done · Canceled. One Roof moves tickets between these (a session launching moves its ticket to In Progress)."),
        ("Type labels", "One label per ticket: Deliverable · Bug · Task · Spike · Decision. New items from One Roof get one; the roadmap shows it as a sticker."),
    ]
}
