import AppKit
import OneRoofCore

/// Right-click › Run in Terminal (LAB-598): the selected command is typed into the agent's run terminal — a plain shell
/// in the agent's repo, in a floating window — and NOT run: the owner reads it and presses Return. One run terminal per
/// agent session; a live one is reused.
extension AppModel {
    func runSelection(_ selection: String, from source: BoardItem) {
        // Selected inside a run terminal: it goes to that same run terminal (its parent's), not a new one.
        let parent = source.session.parentSessionId.flatMap { item($0) } ?? source
        let command = RunTerminal.clean(selection)
        guard !command.isEmpty else { return }
        let text = RunTerminal.typed(command)   // every One Roof terminal is zsh: bracketed paste for several lines
        let candidates = items.map {
            RunTerminal.Candidate(id: $0.id, parentSessionId: $0.session.parentSessionId,
                                  alive: $0.liveAgent != nil && $0.status.isLive, createdAt: $0.session.createdAt)
        }
        switch RunTerminal.target(parent: parent.id, among: candidates) {
        case .reuse(let id):
            guard let run = item(id), let agent = run.liveAgent else { return }
            type(text, into: run.paneId ?? agent)
            PopOutWindowController.popOutRun(run, parentId: parent.id, model: self)
        case .create:
            let repo = parent.repoPath ?? parent.session.launchDirectory
            let dir = Workspace.isInsideProjects(repo) ? repo : Workspace.projectsRoot
            var s = Session(name: RunTerminal.name(parent: parent.session.name), agent: .shell, repoPath: dir, lifecycle: .idle)
            s.startInRepo = dir != Workspace.projectsRoot
            s.parentSessionId = parent.id
            // The run terminal lives in its parent's window; the parent stays selected there.
            let ws = workspaceId(of: parent)
            sessionWorkspace[s.id] = ws
            WorkspaceStore.shared.assign(session: s.id, to: ws)
            createPlanned(s, launchNow: true)
            if let w = window(ws) { w.selectedId = parent.id }
            typeWhenReady(s.id, text: text, parentId: parent.id)
        }
    }

    /// LAB-1831 · Scroll's reply box: an instruction typed into the session's agent, then Return.
    func sendInstruction(_ text: String, to item: BoardItem) {
        guard let pane = item.paneId, !text.isEmpty else { return }
        type(text + "\r", into: pane)
    }

    private func type(_ text: String, into pane: String) {
        let rt = runtime
        DispatchQueue.global(qos: .userInitiated).async { try? rt.type(pane: pane, text: text) }
    }

    /// Wait for the new shell (up to ~15 s), pop it out next to its agent, then type the command once it has drawn
    /// its prompt. Typing never includes Return.
    private func typeWhenReady(_ id: String, text: String, parentId: String, tries: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard let run = self.item(id), let agent = run.liveAgent else {
                if tries < 30 { self.typeWhenReady(id, text: text, parentId: parentId, tries: tries + 1) }
                return
            }
            // finishLaunch selects the new session; give the selection back to the agent before popping out.
            if let w = self.window(self.workspaceId(of: run)), w.selectedId == id { w.selectedId = parentId }
            if PopOutWindowController.open[agent] == nil { PopOutWindowController.popOutRun(run, parentId: parentId, model: self) }
            let drawn = (self.lastSnapshotSessions[agent]?.seq ?? 0) > 0
            if (drawn && tries >= 3) || tries >= 30 {
                self.type(text, into: run.paneId ?? agent)
            } else {
                self.typeWhenReady(id, text: text, parentId: parentId, tries: tries + 1)
            }
        }
    }
}
