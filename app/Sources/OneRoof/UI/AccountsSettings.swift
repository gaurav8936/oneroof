import AppKit
import SwiftUI
import OneRoofCore

/// LAB-1999 · Settings › Seats & accounts › Accounts: every agent's accounts (number, name, folder, signed in or not),
/// "+ Add account" (makes the folder only after a confirm, then shows the one-time sign-in command with Copy), Rename
/// and Remove (never deletes the folder). The words and rules live in OneRoofCore (`AccountsPane`), where they are tested.
struct AccountsSettings: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    /// The account whose sign-in command shows under its row (after Add, or from "Sign in…").
    @State private var signIn: String?
    @State private var copied: String?

    var body: some View {
        let list = model.settings.agentAccounts()
        Section("Accounts") {
            Text("An agent can have more than one account where its CLI keeps its whole home, sign-in included, in a folder you choose. Each account is a seat of its own in New session and the bottom bar.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(AgentAccounts.kinds) { k in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(k.displayName).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("+ Add account") { add(k) }
                            .disabled(!AgentAccounts.canAdd(k))
                            .help(AgentAccounts.oneAccountReason(k) ?? "Add \(AgentAccounts.next(k, in: list)?.id ?? k.displayName) (asks first)")
                            .accessibilityLabel("Add a \(k.displayName) account")
                    }
                    ForEach(AccountsPane.rows(list, agent: k)) { r in row(r, list: list) }
                    if let why = AgentAccounts.oneAccountReason(k) {
                        Text(why).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private func row(_ r: AccountsPane.Row, list: [AgentAccount]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentBadge(r.seat, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(r.label).font(.system(size: 12.5, weight: .medium))
                        if let n = r.idNote { Text(n).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 6) {
                        if let f = r.folder { Text(f).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                        Text(r.status).font(.system(size: 11))
                            .foregroundStyle(r.signedIn == false ? t.needsText.color : Color.secondary)
                    }
                }
                Spacer()
                if r.signInCommand != nil, r.signedIn != true {
                    Button("Sign in…") { signIn = signIn == r.id ? nil : r.id }
                        .help("Show the one-time sign-in command for \(r.id)")
                }
                if AgentAccounts.canAdd(r.seat.agent) {
                    Button("Rename…") { rename(r.id, current: r.label) }.accessibilityLabel("Rename \(r.label)")
                }
                if r.canRemove {
                    Button("Remove…") { remove(r.id, list: list) }
                        .help("Take \(r.id) out of One Roof; its folder stays")
                        .accessibilityLabel("Remove \(r.label)")
                }
            }
            if signIn == r.id, let cmd = r.signInCommand { signInBox(cmd, agent: r.seat.agent) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(r.label), \(r.folder ?? ""), \(r.status)")
    }

    private func signInBox(_ cmd: String, agent: AgentKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in once: run this in Terminal. \(AgentAccounts.signInHint(agent))")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(cmd).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.surface.color))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separator.color))
                Button(copied == cmd ? "Copied ✓" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    copied = cmd
                }
                .accessibilityLabel("Copy the sign-in command")
                Button("Done") { signIn = nil }
            }
        }
        .padding(.leading, 28)
    }

    // MARK: Actions

    private func add(_ k: AgentKind) {
        guard let a = AgentAccounts.next(k, in: model.settings.agentAccounts()) else { return }
        let folder = a.folder()
        let exists = Workspace.folderExists(folder)
        let c = AccountsPane.addConfirm(a, folderExists: exists)
        let alert = NSAlert()
        alert.messageText = c.title
        alert.informativeText = c.message
        alert.addButton(withTitle: c.button); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if !exists {
            do { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) } catch {
                let e = NSAlert(); e.messageText = "Could not create \(AgentAccounts.short(folder))"; e.informativeText = error.localizedDescription
                e.runModal(); return
            }
        }
        model.settings.addAccount(k)
        signIn = a.id
        copied = nil
    }

    private func rename(_ id: String, current: String) {
        let alert = NSAlert()
        alert.messageText = "Rename \(id)"
        alert.informativeText = "The name shows here, in New session and in the bottom bar's help. Sessions keep the account id (\(id)). Leave it empty for \(id)."
        let field = NSTextField(string: current)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.settings.renameAccount(id, to: field.stringValue)
    }

    private func remove(_ id: String, list: [AgentAccount]) {
        guard let a = list.first(where: { $0.id == id }) else { return }
        let c = AccountsPane.removeConfirm(a)
        let alert = NSAlert()
        alert.messageText = c.title
        alert.informativeText = c.message
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.settings.removeAccount(id)
        if signIn == id { signIn = nil }
    }
}
