import Darwin
import Foundation

/// Reads another process's argv and environment with sysctl(KERN_PROCARGS2).
///
/// Works for the owner's own non-system processes (claude, codex, kimi, agy). macOS returns no environment
/// for SIP-protected Apple binaries such as /bin/sleep — callers must treat an empty result as "unknown".
/// (gotcha 20261017_macos_hides_environment_of_apple_system_binaries_in_kern_procargs2)
public enum ProcessProbe {
    public struct Args: Equatable, Sendable {
        public var executable: String
        public var argv: [String]
        public var env: [String: String]
    }

    public static func args(pid: Int32) -> Args? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buf.prefix(size)))
    }

    /// Parse a KERN_PROCARGS2 buffer: int32 argc, exec path, NUL padding, argv[argc], env…
    public static func parse(_ buf: [UInt8]) -> Args? {
        guard buf.count >= 4 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        func readString() -> String? {
            guard i < buf.count else { return nil }
            let start = i
            while i < buf.count && buf[i] != 0 { i += 1 }
            let s = String(decoding: buf[start..<i], as: UTF8.self)
            return s
        }
        func skipNULs() { while i < buf.count && buf[i] == 0 { i += 1 } }

        guard let exe = readString() else { return nil }
        skipNULs()
        var argv: [String] = []
        for _ in 0..<max(argc, 0) {
            guard let a = readString() else { break }
            argv.append(a)
            i += 1
        }
        var env: [String: String] = [:]
        while i < buf.count {
            skipNULs()
            guard let e = readString(), !e.isEmpty else { break }
            if let eq = e.firstIndex(of: "=") {
                env[String(e[..<eq])] = String(e[e.index(after: eq)...])
            }
            i += 1
        }
        return Args(executable: exe, argv: argv, env: env)
    }
}
