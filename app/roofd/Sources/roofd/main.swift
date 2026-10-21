import Darwin
import Foundation
import RoofVT

// roofd: One Roof's session manager (LAB-ROOFD, T14). One binary, several modes:
//   roofd daemon                          the control plane (launchd runs it)
//   roofd session --spec-stdin            one holder per session (started by the daemon; spec on stdin)
//   roofd attach <id>                     what a terminal surface runs to show a session
//   roofd hello | list | info <id> | read <id> [lines] | input <id> <text> [--submit] | close <id>
//   roofd create --id <id> [--cwd D] [--label L] [--cols N --rows N] [--env K=V ...] -- <argv...>
// ROOFD_DIR overrides the socket folder (tests, the spike harness).

let args = Array(CommandLine.arguments.dropFirst())

// Whoever started roofd may have ignored or blocked signals (an app launched from some shells ignores SIGTERM):
// take the defaults back, so `kill`, launchd and logout can always stop it.
for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] { signal(sig, SIG_DFL) }
// Never throttled like a background app (timer coalescing, App Nap): sessions answer, redraw and report status on time.
let roofdActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "roofd runs agent sessions")
var none = sigset_t()
sigemptyset(&none)
sigprocmask(SIG_SETMASK, &none, nil)

func printJSON(_ o: Any) {
    if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(d)
        print()
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("roofd: \(msg)\n".utf8))
    exit(1)
}

func call(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
    do { return try Sock.request(Paths.control, ["method": method, "params": params], timeout: 10) }
    catch { fail("\(error)") }
}

switch args.first {
case "daemon":
    do { try Daemon.run() } catch { fail("\(error)") }
case "session":
    // The spec arrives on stdin (never argv: it carries the session's environment); then stdin is /dev/null.
    guard args.contains("--spec-stdin"),
          let j = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any]
    else { fail("session: no spec") }
    let devnull = open("/dev/null", O_RDONLY)
    if devnull >= 0 { dup2(devnull, 0); close(devnull) }
    do {
        let h = try Holder(spec: try Holder.Spec(json: j))
        try h.start()
        h.run()
    } catch { fail("\(error)") }
case "report":
    // Called by agent hooks (Claude: SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop, …) with the hook
    // payload on stdin. Outside a One Roof session it does nothing; it always exits 0 and never makes the agent wait.
    let env = ProcessInfo.processInfo.environment
    guard let id = env["ONEROOF_SESSION"], let control = env["ONEROOF_ROOFD"], Paths.validId(id) else { exit(0) }
    let payload = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any] ?? [:]
    let holder = (control as NSString).deletingLastPathComponent + "/\(id).sock"
    _ = try? Sock.holderRequest(holder, ["op": "report", "agent": args.count > 1 ? args[1] : "claude",
                                         "event": payload["hook_event_name"] as? String ?? "",
                                         "message": payload["message"] as? String ?? "",
                                         "path": WorkPath.from(hook: payload) ?? ""], timeout: 1)
    exit(0)
case "attach":
    guard args.count > 1 else { fail("attach <id>") }
    exit(Attach.run(args[1]))
case "hello":
    printJSON(call("hello"))
case "list":
    printJSON(call("list"))
case "info", "close":
    guard args.count > 1 else { fail("\(args[0]) <id>") }
    printJSON(call(args[0], ["id": args[1]]))
case "read":
    guard args.count > 1 else { fail("read <id> [lines]") }
    let r = call("read", ["id": args[1], "lines": args.count > 2 ? Int(args[2]) ?? 0 : 0])
    print(r["text"] as? String ?? "", terminator: "")
case "input":
    guard args.count > 2 else { fail("input <id> <text> [--submit]") }
    printJSON(call("input", ["id": args[1], "text": args[2], "submit": args.contains("--submit")]))
case "create":
    var p: [String: Any] = ["cwd": FileManager.default.currentDirectoryPath]
    var env = ProcessInfo.processInfo.environment
    var i = 1
    while i < args.count {
        let a = args[i]
        if a == "--" { p["argv"] = Array(args[(i + 1)...]); break }
        guard i + 1 < args.count else { fail("missing value for \(a)") }
        let v = args[i + 1]
        switch a {
        case "--id": p["id"] = v
        case "--cwd": p["cwd"] = v
        case "--label": p["label"] = v
        case "--cols": p["cols"] = Int(v)
        case "--rows": p["rows"] = Int(v)
        case "--env": let kv = v.split(separator: "=", maxSplits: 1); if kv.count == 2 { env[String(kv[0])] = String(kv[1]) }
        default: fail("unknown option \(a)")
        }
        i += 2
    }
    if p["argv"] == nil { p["argv"] = ["/bin/zsh", "-l", "-i"] }
    if env["TERM"] == nil || env["TERM"] == "dumb" { env["TERM"] = "xterm-256color" }
    p["env"] = env
    printJSON(call("create", p))
case "vt-replay":
    // Harness only (M3): feed stdin into a fresh terminal of <cols> x <rows>, print its state as JSON.
    guard args.count > 2, let cols = UInt16(args[1]), let rows = UInt16(args[2]), let t = rvt_new(cols, rows, 8 << 20) else {
        fail("vt-replay <cols> <rows> < bytes")
    }
    let input = [UInt8](FileHandle.standardInput.readDataToEndOfFile())
    input.withUnsafeBufferPointer { rvt_feed(t, $0.baseAddress, $0.count) }
    var p: UnsafeMutablePointer<UInt8>?
    let n = rvt_text(t, UInt32(args.count > 3 ? Int(args[3]) ?? 0 : 0), &p)
    let text = p.map { String(decoding: UnsafeBufferPointer(start: $0, count: n), as: UTF8.self) } ?? ""
    if let p { rvt_bytes_free(p, n) }
    var x: UInt16 = 0, y: UInt16 = 0
    let alt = rvt_cursor(t, &x, &y)
    let modes = [1, 25, 1000, 1002, 1003, 1006, 1049, 2004].filter { rvt_mode(t, UInt16($0), false) }
    printJSON(["text": text, "x": Int(x), "y": Int(y), "alt": alt, "modes": modes])
    rvt_free(t)
default:
    fail("usage: roofd daemon | attach <id> | create --id <id> -- <argv> | list | info | read | input | close | hello")
}
