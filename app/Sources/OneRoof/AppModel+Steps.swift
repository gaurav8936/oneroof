import Foundation
import OneRoofCore

/// Steps in a session (LAB-259): rewinding the terminal to one, and asking a model to explain one.
extension AppModel {
    /// How much of the terminal a rewind or an explanation reads (the chapter list itself reads the last 300 lines).
    static let stepReadLines = 5000

    enum StepExplainState: Equatable {
        case working
        case done(StepExplanation)
        case failed(String)
    }

    static func stepKey(_ item: BoardItem, _ chapter: Chapter) -> String { "\(item.id)#\(chapter.index)#\(chapter.title)" }

    /// Lines above the bottom where a step starts, read fresh from the session (nil: not in the last 5,000 lines).
    func stepOffset(_ item: BoardItem, _ chapter: Chapter, done: @escaping (Int?) -> Void) {
        guard let pane = item.paneId else { done(nil); return }
        let r = runtime
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? r.read(pane: pane, lines: Self.stepReadLines)) ?? ""
            let n = StepExplainer.linesFromBottom(title: chapter.title, in: text)
            DispatchQueue.main.async { done(n) }
        }
    }

    /// Ask Claude (headless, no tools, nothing saved) to explain one step; the answer lands in `stepExplanations`.
    func explainStep(_ item: BoardItem, _ chapter: Chapter) {
        let key = Self.stepKey(item, chapter)
        if case .working? = stepExplanations[key] { return }
        guard let pane = item.paneId else { stepExplanations[key] = .failed("The session is not running."); return }
        stepExplanations[key] = .working
        let r = runtime
        // The session's own Claude account when it is a Claude session; otherwise the default one.
        let account = item.session.agent == .claude ? item.account : settings.defaults(for: .claude).account
        var env = ProcessInfo.processInfo.environment
        for k in AccountResolver.accountVariables { env[k] = nil }
        env.merge(AccountResolver.launchEnv(agent: .claude, account: account)) { _, b in b }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = (try? r.read(pane: pane, lines: Self.stepReadLines)) ?? ""
            let result: StepExplainState
            if let step = StepExplainer.stepText(title: chapter.title, in: text) {
                let out = Self.runHeadless(StepExplainer.prompt(title: chapter.title, transcript: step), env: env, timeout: 120)
                if let e = out.text.flatMap(StepExplainer.parse) { result = .done(e) }
                else { result = .failed(out.error ?? "The model's answer could not be read.") }
            } else {
                result = .failed("This step is no longer in the session's last \(Self.stepReadLines) lines.")
            }
            DispatchQueue.main.async { self?.stepExplanations[key] = result }
        }
    }

    /// `claude -p` in a login shell from the workspace root (agents run only there), prompt on stdin.
    static func runHeadless(_ prompt: String, env: [String: String], timeout: TimeInterval) -> (text: String?, error: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", StepExplainer.command]
        p.currentDirectoryURL = URL(fileURLWithPath: Workspace.projectsRoot)
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        do { try p.run() } catch { return (nil, "Could not start claude: \(error.localizedDescription)") }
        inPipe.fileHandleForWriting.write(Data(prompt.utf8))
        try? inPipe.fileHandleForWriting.close()
        var out = Data(), err = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { out = outPipe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { err = errPipe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if g.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return (nil, "No answer within \(Int(timeout)) seconds.")
        }
        p.waitUntilExit()
        let text = String(decoding: out, as: UTF8.self)
        if p.terminationStatus != 0 {
            let e = String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, "claude stopped (\(p.terminationStatus)): " + String((e.isEmpty ? text : e).prefix(200)))
        }
        return (text, nil)
    }
}
