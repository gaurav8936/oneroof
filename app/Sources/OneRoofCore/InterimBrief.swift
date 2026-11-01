import Foundation

// LAB-1971 · the automatic interim brief for agents with no session-start hook (OpenCode, Goose). Claude, Codex, Gemini
// and Kimi get it from the kit's session-orientation hook; for these two One Roof asks the kit at launch
// (`python3 -m ae.handoff interim --if-active`, facts only, ≤3 s) and puts the brief before the opening message.
// The kit prints nothing when no other session or long job is active, and then the opening message is unchanged.
public enum InterimBrief {
    /// Agents whose CLI has no session-start hook, so the brief rides in the opening message.
    public static func needsOpeningBrief(_ agent: AgentKind) -> Bool { agent.isHosted }

    /// The opening message with the brief in front; the opening alone when the brief is empty.
    public static func opening(brief: String, opening: String?) -> String? {
        let b = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = (opening ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return opening }
        if o.isEmpty { return b + "\n\nRead the brief above, then wait for the owner's first instruction." }
        return b + "\n\n---\n\n" + (opening ?? "")
    }

    public typealias Runner = (_ exe: String, _ args: [String], _ cwd: String, _ env: [String: String]) -> (Int32, String)

    /// Ask the kit for the brief. Empty on any failure: a missing kit or a slow machine must never stop a launch.
    public static func fetch(runtime: HostedRuntimeConfiguration, cwd: String, run: Runner? = nil) -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: runtime.pythonExecutable),
              fm.fileExists(atPath: runtime.kitDirectory + "/ae/handoff.py") else { return "" }
        let runner: Runner = run ?? { exe, args, cwd, env in Foundations.run(exe, args, cwd: cwd, timeout: 6, environment: env) }
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = runtime.kitDirectory
        let r = runner(runtime.pythonExecutable, ["-m", "ae.handoff", "interim", "--if-active", "--budget", "3"], cwd, env)
        return r.0 == 0 ? r.1 : ""
    }
}
