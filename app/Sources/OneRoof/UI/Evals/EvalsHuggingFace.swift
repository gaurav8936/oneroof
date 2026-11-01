import AppKit
import Security
import SwiftUI
import OneRoofCore

// LAB-2117 · the user's own Hugging Face account for gated eval datasets: the token lives in the Keychain (never in a
// file, never in the app), "Test" asks Hugging Face who it belongs to, and each gated set is unlocked only once the user
// says they accepted its terms on Hugging Face. The engine gets the token for its own process only (EvalEngine.hfEnvironment).

final class HFAccount: ObservableObject {
    static let shared = HFAccount()

    /// A token is saved in the Keychain.
    @Published private(set) var signedIn = false
    /// Who Hugging Face says the token belongs to, after Test.
    @Published private(set) var user: String?
    @Published private(set) var testing = false
    @Published private(set) var testResult: String?
    /// Gated sets whose terms the user accepted on Hugging Face (ticked in Settings › Evals).
    @Published private(set) var accepted: Set<String> = []

    private let io = DispatchQueue(label: "oneroof.evals.hf")
    private let lock = NSLock()
    private var token: String?
    private var loaded = false
    /// `accepted` for the engine's queue (read under `lock`; never a hop to main, which may be waiting on the engine).
    private var acceptedSnapshot: Set<String> = []
    private static let acceptedKey = "evals.hf.accepted"
    /// A fresh profile (--fresh-profile, self-tests) uses its own Keychain item, so it starts signed out.
    private static var account: String { Prefs.freshProfile ? "huggingface-token.fresh" : "huggingface-token" }
    private static let service = "One Roof · Hugging Face"

    private init() {
        accepted = Set(Prefs.defaults.stringArray(forKey: Self.acceptedKey) ?? [])
        acceptedSnapshot = accepted
        io.async { [weak self] in self?.loadToken() }
    }

    /// Hand the engine the user's sign-in (called when Evals starts; idempotent).
    func install() {
        EvalEngine.extraEnvironment = { [weak self] in self?.engineEnvironment() ?? [:] }
    }

    func engineEnvironment() -> [String: String] {
        loadToken()
        lock.lock(); defer { lock.unlock() }
        var e: [String: String] = [:]
        if let token { e["HF_TOKEN"] = token }
        e["ONEROOF_HF_ACCEPTED"] = EvalGate.acceptedEnv(acceptedSnapshot)
        return e
    }

    func status(_ s: EvalDataSource?) -> EvalGate.Status { EvalGate.status(s, signedIn: signedIn, accepted: accepted) }

    func setAccepted(_ folder: String, _ on: Bool) {
        if on { accepted.insert(folder) } else { accepted.remove(folder) }
        Prefs.defaults.set(accepted.sorted(), forKey: Self.acceptedKey)
        lock.lock(); acceptedSnapshot = accepted; lock.unlock()
    }

    /// Save a pasted token to the Keychain (refused when it doesn't look like a Hugging Face token), then test it.
    func signIn(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EvalGate.looksLikeToken(t) else { testResult = "That isn't a Hugging Face access token (it starts with hf_)."; return }
        io.async { [weak self] in
            let ok = Self.keychainSave(t)
            self?.lock.lock(); if ok { self?.token = t }; self?.lock.unlock()
            DispatchQueue.main.async {
                guard let self else { return }
                if ok { self.signedIn = true; self.test() } else { self.testResult = "The Keychain refused to save the token." }
            }
        }
    }

    func signOut() {
        io.async { [weak self] in
            Self.keychainDelete()
            self?.lock.lock(); self?.token = nil; self?.lock.unlock()
            DispatchQueue.main.async { self?.signedIn = false; self?.user = nil; self?.testResult = "Signed out. Gated sets are locked again." }
        }
    }

    /// Ask Hugging Face who the token belongs to (whoami); nothing else is sent.
    func test() {
        testing = true
        io.async { [weak self] in
            guard let self else { return }
            self.loadToken()
            self.lock.lock(); let t = self.token; self.lock.unlock()
            guard let t, let url = URL(string: "https://huggingface.co/api/whoami-v2") else {
                DispatchQueue.main.async { self.testing = false; self.testResult = "Not signed in." }
                return
            }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let name = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["name"] as? String
                DispatchQueue.main.async {
                    self.testing = false
                    if code == 200, let name { self.user = name; self.testResult = "Signed in as \(name)." }
                    else if code == 401 { self.user = nil; self.testResult = "Hugging Face refused the token (401): make a new one and sign in again." }
                    else { self.testResult = "Could not reach Hugging Face" + (err.map { ": \($0.localizedDescription)" } ?? " (HTTP \(code)).") }
                }
            }.resume()
        }
    }

    private func loadToken() {
        lock.lock()
        if loaded { lock.unlock(); return }
        loaded = true
        lock.unlock()
        let t = Self.keychainRead()
        lock.lock(); token = t; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.signedIn = t != nil }
    }

    // MARK: Keychain (generic password, this app only)

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func keychainRead() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func keychainSave(_ token: String) -> Bool {
        keychainDelete()
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    private static func keychainDelete() { SecItemDelete(query() as CFDictionary) }
}

// MARK: - Views

/// "Data: cais/hle (Hugging Face) · Licence MIT · Downloaded to this Mac on first use; One Roof does not ship it."
struct EvalsSourceLine: View {
    @Environment(\.theme) private var t
    let source: EvalDataSource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(EvalSources.line(source)).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                .fixedSize(horizontal: false, vertical: true)
            if let u = URL(string: source.url) {
                Link("Source ↗", destination: u).font(.system(size: TypeScale.caption, weight: .semibold))
                    .accessibilityLabel("Open the data source, \(source.origin)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A locked gated set: what to do, the terms link, and Settings › Evals.
struct EvalsLockCard: View {
    @Environment(\.theme) private var t
    let name: String
    let source: EvalDataSource
    let status: EvalGate.Status

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(t.needsText.color).accessibilityHidden(true)
                    Text("\(name) is locked").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                }
                Text(EvalSources.lockedLine).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text("1. Open the dataset on Hugging Face, sign in with your own account and accept its terms.\n2. In One Roof: Settings › Evals › Hugging Face account, sign in with your own access token (read).\n3. Tick \(name) there once Hugging Face shows you have access.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Text("Until then there is no run, no question browsing and no download. One Roof never ships this data or uses anyone else's token.")
                    .ui(TypeScale.small).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let u = source.termsURL.flatMap(URL.init(string:)) {
                        Link("Open the terms ↗", destination: u).font(.system(size: TypeScale.small, weight: .semibold))
                    }
                    RoofButton("Settings › Evals") { NotificationCenter.default.post(name: .openEvalsSettings, object: nil) }
                }
                Text(status.label).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.needsText.color)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) is locked. \(EvalSources.lockedLine)")
    }
}

extension Notification.Name {
    /// LAB-2117: open Settings on the Evals pane (from a locked benchmark).
    static let openEvalsSettings = Notification.Name("oneroof.openEvalsSettings")
}

/// Settings › Evals: the Hugging Face account and the gated sets.
struct EvalsSettingsPane: View {
    @ObservedObject var hf = HFAccount.shared
    @State private var pasted = ""

    var body: some View {
        Form {
            Section("Evals") {
                Text("\(EvalsDraft.banner). \(EvalsDraft.detail)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Hugging Face account") {
                LabeledContent("Status") {
                    Text(hf.signedIn ? (hf.user.map { "Signed in as \($0)" } ?? "Token saved in the Keychain") : "Not signed in")
                }
                if hf.signedIn {
                    HStack {
                        Button(hf.testing ? "Testing…" : "Test") { hf.test() }.disabled(hf.testing)
                        Button("Sign out") { hf.signOut() }
                    }
                } else {
                    HStack {
                        Text("Your own access token")
                        SecureField("", text: $pasted, prompt: Text("hf_…")).textFieldStyle(.roundedBorder).labelsHidden()
                            .frame(minWidth: 220, maxWidth: 320)
                            .accessibilityLabel("Hugging Face access token")
                        Button("Sign in") { hf.signIn(pasted); pasted = "" }.disabled(pasted.isEmpty)
                    }
                    if let u = URL(string: "https://huggingface.co/settings/tokens") {
                        Link("Make a read token on Hugging Face ↗", destination: u).font(.caption)
                    }
                }
                if let r = hf.testResult { Text(r).font(.caption).foregroundStyle(.secondary) }
                Text("Only for gated datasets. The token stays in your Keychain and is given to the eval engine's own process when it downloads or runs a gated set; it is never written to a file or shipped. One Roof never uses a token cached by another tool.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Gated datasets") {
                ForEach(EvalSources.gatedFolders, id: \.self) { f in
                    if let s = EvalSources.table[f] {
                        let st = hf.status(s)
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle(isOn: Binding(get: { hf.accepted.contains(f) }, set: { hf.setAccepted(f, $0) })) {
                                HStack {
                                    Text(EvalsSettingsPane.title(f))
                                    Text(st.label).font(.caption.monospaced()).foregroundStyle(st.locked ? Color.primary : Color.secondary)
                                }
                            }
                            .disabled(!hf.signedIn)
                            .accessibilityLabel("\(EvalsSettingsPane.title(f)): I accepted the terms on Hugging Face. \(st.label)")
                            HStack(spacing: 8) {
                                Text("\(s.origin) · Licence \(s.licence)").font(.caption).foregroundStyle(.secondary)
                                if let u = s.termsURL.flatMap(URL.init(string:)) { Link("Terms ↗", destination: u).font(.caption) }
                            }
                        }
                    }
                }
                Text("Tick a set once Hugging Face shows you have access to it. If the terms were not really accepted, Hugging Face refuses the download and the set says so.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func title(_ folder: String) -> String {
        ["hle": "Humanity's Last Exam (HLE)", "gaia": "GAIA", "livecodebench_pro": "LiveCodeBench Pro", "xstest": "XSTest"][folder] ?? folder
    }
}
