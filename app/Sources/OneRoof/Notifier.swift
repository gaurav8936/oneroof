import AppKit
import UserNotifications
import OneRoofCore

/// Desktop notifications (LAB-197): macOS banners when an agent needs you, finishes its turn, or a long command ends
/// in a terminal you are not looking at. The rules live in OneRoofCore (`NoteGate`); this posts what they allow and
/// brings the session forward when a banner is clicked. Never auto-answers anything.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    weak var model: AppModel?
    private var gate = NoteGate()
    /// LAB-718: macOS's own answer is read every time (it is cheap); nothing is cached, so allowing One Roof in
    /// System Settings works at once, and the prompt is shown at most once per launch, only when macOS was never asked.
    private var askedThisLaunch = false
    private var checking = false
    private var waiting: [Note] = []
    /// Decisions already announced (a decision is announced once, when it opens).
    private var announced = Set<UUID>()

    /// Notifications need a real app bundle (UNUserNotificationCenter stops the process without one, e.g. `swift run`)
    /// and never fire from a self-test.
    static var available: Bool {
        !SelfTest.isActive && Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private var center: UNUserNotificationCenter? { Self.available ? UNUserNotificationCenter.current() : nil }

    func attach(_ model: AppModel) {
        self.model = model
        center?.delegate = self
    }

    // MARK: Permission

    /// Ask macOS (from Settings, or lazily on the first note when macOS was never asked). `done` gets the answer on
    /// the main thread.
    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        guard let center else { done?(false); return }
        askedThisLaunch = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async {
                if ok { self.waiting.forEach(self.deliver) }
                self.waiting = []
                done?(ok)
            }
        }
    }

    /// What macOS says right now.
    func permission(_ done: @escaping (NotePermissionStatus) -> Void) {
        guard let center else { done(.unavailable); return }
        center.getNotificationSettings { s in
            let st: NotePermissionStatus
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: st = .allowed
            case .denied: st = .denied
            default: st = .notAsked
            }
            DispatchQueue.main.async { done(st) }
        }
    }

    /// What Settings shows: "On", "Off in System Settings", "Not asked yet", or "Not available" (no app bundle).
    func status(_ done: @escaping (String) -> Void) {
        permission { done(NotePermission.settings($0).text) }
    }

    // MARK: Events

    func post(_ e: NoteEvent) {
        guard center != nil, let model else { return }
        guard let note = gate.decide(e, prefs: NotePrefs(model.settings), appActive: NSApp.isActive,
                                     focusedSession: focusedSession()) else { return }
        waiting.append(note)
        guard !checking else { return }
        checking = true
        permission { st in
            self.checking = false
            let notes = self.waiting
            switch NotePermission.action(st, askedThisLaunch: self.askedThisLaunch) {
            case .deliver: self.waiting = []; notes.forEach(self.deliver)
            case .drop: self.waiting = []
            case .ask: self.requestAuthorization()
            }
        }
    }

    /// New open decisions → "needs you" with the decision's title (Claude wants to run swift test).
    func decisionsChanged(_ ds: [Decision], names: [String: String], now: Date = Date()) {
        for d in ds where d.isOpen && !announced.contains(d.id) {
            announced.insert(d.id)
            // Decisions loaded from the store at launch are old news.
            guard now.timeIntervalSince(d.askedAt) < 120 else { continue }
            post(NoteEvent(kind: .needsYou, sessionId: d.sessionId, sessionName: names[d.sessionId] ?? "", detail: d.title, at: now))
        }
    }

    /// The session whose terminal has focus in the key window; else the selected row of the main window in front.
    func focusedSession() -> String? {
        guard let model, let key = NSApp.keyWindow else { return nil }
        if let tv = key.firstResponder as? TerminalSurfaceView, let rid = tv.runtimeId {
            return model.items.first { $0.liveAgent == rid }?.id
        }
        if key.windowController is MainWindowController { return model.active.selectedId }
        return nil
    }

    private func deliver(_ n: Note) {
        guard let center else { return }
        let c = UNMutableNotificationContent()
        c.title = n.title
        c.body = n.body
        c.threadIdentifier = n.threadIdentifier
        c.sound = n.kind == .needsYou ? .default : nil
        c.userInfo = ["session": n.sessionId, "kind": n.kind.rawValue]
        center.add(UNNotificationRequest(identifier: n.identifier, content: c, trigger: nil))
    }

    /// The session is gone: drop its banners.
    func clear(session: String) {
        gate.forget(session: session)
        center?.removeDeliveredNotifications(withIdentifiers: NoteKind.allCases.map { NoteGate.identifier($0, session: session) })
    }

    // MARK: UNUserNotificationCenterDelegate

    /// One Roof in front but showing another session: still show the banner (the gate already dropped the focused one).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Click → select the session and bring its window to the front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sid = response.notification.request.content.userInfo["session"] as? String
        DispatchQueue.main.async {
            if let sid { self.model?.showSession(sid) }
            completionHandler()
        }
    }
}

extension AppModel {
    /// Bring a session forward wherever it is: its own window (popped out or a roof window), else its workspace window.
    func showSession(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        guard let item = item(id) else { return }
        if let agent = item.liveAgent {
            if let r = RoofWindowController.owner(of: agent) { r.window?.makeKeyAndOrderFront(nil); return }
            if let c = PopOutWindowController.open[agent] { c.show(); return }
        }
        reveal(item)
    }

    /// Give a terminal surface its session and its hooks: notifications for long commands and programs' own
    /// notifications (LAB-197), Right-click › Run in Terminal (LAB-598).
    func wire(_ surface: TerminalSurfaceView, agent: String) {
        surface.runtimeId = agent
        surface.onCommandFinished = { [weak self] code, seconds in
            guard let self, let item = self.items.first(where: { $0.liveAgent == agent }) else { return }
            Notifier.shared.post(NoteEvent(kind: .longCommand, sessionId: item.id, sessionName: item.session.name,
                                           duration: seconds, exitCode: code))
        }
        surface.onDesktopNotification = { [weak self] title, body in
            guard let self, let item = self.items.first(where: { $0.liveAgent == agent }) else { return }
            Notifier.shared.post(NoteEvent(kind: .terminal, sessionId: item.id, sessionName: item.session.name,
                                           detail: body, title: title))
        }
        surface.onRunSelection = { [weak self] text in
            guard let self, let item = self.items.first(where: { $0.liveAgent == agent }) else { return }
            self.runSelection(text, from: item)
        }
    }

    /// Status changes after a poll → "ready" notes (finished turns).
    func notifyStatusChanges(before: [String: SessionStatus], after: [BoardItem]) {
        guard Notifier.available else { return }
        for i in after {
            guard let kind = NoteSignals.statusChange(from: before[i.id], to: i.status) else { continue }
            var detail = captions[i.id]?.text
            if let d = detail, d.hasPrefix("Ready · ") { detail = String(d.dropFirst("Ready · ".count)) }
            else if detail?.hasPrefix("Ready") != true { detail = nil }
            Notifier.shared.post(NoteEvent(kind: kind, sessionId: i.id, sessionName: i.session.name, detail: detail))
        }
    }
}
