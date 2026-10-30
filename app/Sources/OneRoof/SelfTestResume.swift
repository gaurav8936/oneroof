import Foundation
import OneRoofCore

/// LAB-1583 · resume stress test: `resumeall [max]` presses Resume on every catalog row that offers it (oldest
/// conversation ids too), one at a time, as All sessions does; waits for the session's terminal; reads its screen; logs
/// a verdict per row; then closes it again. Run only on a copy of the real profile with its own roofd (ROOFD_DIR).
/// Verdicts: resumed (the agent is in the foreground with no error on screen) · error (Claude or the shell said so) ·
/// nothing (no terminal appeared) · noagent (a terminal, but no agent came up). Results: <out>-resume.tsv.
enum SelfTestResume {
    static func run(_ app: AppDelegate, out: String, max: Int, done: @escaping () -> Void) {
        let m = app.model
        let rows = m.catalogEntries().filter { $0.resume != .open && $0.resume.buttonTitle != nil && $0.state == .history }
        let list = Array(rows.prefix(max))
        SelfTestScript.log(out, "  resumeall: \(list.count) of \(rows.count) rows with a Resume button")
        try? "id\tname\tagent\tresume\tverdict\tms\tscreen\n".write(toFile: out + "-resume.tsv", atomically: true, encoding: .utf8)
        next(list, 0, app: app, out: out, done: done)
    }

    private static func next(_ list: [SessionCatalog.Entry], _ k: Int, app: AppDelegate, out: String, done: @escaping () -> Void) {
        guard k < list.count else { done(); return }
        let e = list[k], m = app.model, started = Date()
        m.lastError = nil
        m.catalogResume(e.id)
        poll(e, m: m, started: started) { verdict, screen in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let line = [e.id, e.name, e.agent, e.resume.buttonTitle ?? "", verdict, "\(ms)", screen].map {
                $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ⏎ ")
            }.joined(separator: "\t") + "\n"
            if let h = FileHandle(forWritingAtPath: out + "-resume.tsv") { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
            SelfTestScript.log(out, "  \(k + 1)/\(list.count) \(verdict) \(ms)ms · \(e.name)")
            m.catalogClose(e.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { next(list, k + 1, app: app, out: out, done: done) }
        }
    }

    /// Up to 30 s: settle as soon as an agent is up and its screen has stopped changing, or an error shows.
    private static func poll(_ e: SessionCatalog.Entry, m: AppModel, started: Date, last: String = "", _ finish: @escaping (String, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let waited = Date().timeIntervalSince(started)
            let it = m.item(e.id)
            if let err = m.lastError { finish("error", "app: " + err); return }
            let pane = it?.paneId ?? it?.endedShell
            let screen = pane.flatMap { try? m.runtime.read(pane: $0, lines: 40) } ?? ""
            let tail = screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(8).joined(separator: "\n")
            if let bad = ResumeVerdict.error(in: screen) { finish("error", bad + " | " + tail); return }
            if it?.liveAgent != nil, screen == last, !screen.isEmpty { finish("resumed", tail); return }
            if waited > 30 { finish(pane == nil ? "nothing" : (it?.liveAgent == nil ? "noagent" : "resumed-busy"), tail); return }
            poll(e, m: m, started: started, last: screen, finish)
        }
    }
}

/// What a failed resume prints (Claude's own messages and the shell's).
enum ResumeVerdict {
    static let errors = ["No conversation found", "not found", "command not found", "Invalid session", "Error:", "error:"]
    static func error(in screen: String) -> String? {
        errors.first { screen.contains($0) }
    }
}
