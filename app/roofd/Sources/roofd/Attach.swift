import CRoofSpawn
import Darwin
import Foundation
import OneRoofCore

/// `roofd attach <id>`: what a libghostty surface runs. Transparent: no screen, keys or alternate screen of its own;
/// it moves bytes between its terminal (raw mode) and the session, and exits with the child's code (T14 §3c).
enum Attach {
    static func run(_ id: String) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGWINCH) { _ in }   // only to interrupt poll()
        guard let fd = Sock.connect(Paths.session(id)) else {
            FileHandle.standardError.write(Data("roofd: no session \(id)\n".utf8))
            return 1
        }
        var cols: UInt16 = 120, rows: UInt16 = 40
        let tty = isatty(0) != 0
        if tty {
            _ = roof_make_raw(0)
            // LAB-606: the redraw is built for the size in the hello; wait until the terminal has its real size.
            var settle = SizeSettle()
            for _ in 0..<SizeSettle.maxReads {
                var c: UInt16 = 0, r: UInt16 = 0
                if roof_get_winsize(0, &c, &r) == 0 {
                    if c > 0, r > 0 { (cols, rows) = (c, r) }
                    if settle.read(cols: c, rows: r) { break }
                }
                usleep(SizeSettle.intervalMicros)
            }
        }
        defer { if tty { roof_restore_tty(0) } }
        let history = Int(ProcessInfo.processInfo.environment["ROOFD_HISTORY"] ?? "") ?? 5000
        Sock.writeAll(fd, Wire.encode(.hello, json: ["proto": 1, "cols": Int(cols), "rows": Int(rows), "role": "primary",
                                                     "redraw": true, "history": history]))
        var inbuf: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 256 * 1024)
        var stdinOpen = true
        var cleared = false
        while true {
            if tty {
                var c: UInt16 = 0, r: UInt16 = 0
                if roof_get_winsize(0, &c, &r) == 0, (c, r) != (cols, rows), c > 0, r > 0 {
                    (cols, rows) = (c, r)
                    Sock.writeAll(fd, Wire.encode(.resize, [UInt8(c >> 8), UInt8(c & 0xff), UInt8(r >> 8), UInt8(r & 0xff)]))
                }
            }
            var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
            if stdinOpen { fds.append(pollfd(fd: 0, events: Int16(POLLIN), revents: 0)) }
            let n = poll(&fds, nfds_t(fds.count), 250)
            if n < 0 { if errno == EINTR { continue }; return 1 }
            if fds.count > 1, fds[1].revents != 0 {
                let k = read(0, &buf, buf.count)
                if k > 0 { Sock.writeAll(fd, Wire.encode(.input, Array(buf[0..<k]))) } else { stdinOpen = false }
            }
            if fds[0].revents != 0 {
                let k = read(fd, &buf, buf.count)
                if k <= 0 { return 0 }
                inbuf += buf[0..<k]
                // Output frames go straight from the receive buffer to the terminal, without a copy.
                var off = 0
                while inbuf.count - off >= 5 {
                    let n = Int(inbuf[off + 1]) << 24 | Int(inbuf[off + 2]) << 16 | Int(inbuf[off + 3]) << 8 | Int(inbuf[off + 4])
                    guard inbuf.count - off - 5 >= n else { break }
                    let type = Frame(rawValue: inbuf[off])
                    if type == .redraw, !cleared {
                        // Start from a blank terminal: login(1) has already printed "Last login: …" into it, and the
                        // session's screen was drawn over those lines (Claude's header overlapped them, owner 10-20).
                        cleared = true
                        let clear: [UInt8] = Array("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8)
                        _ = clear.withUnsafeBytes { write(1, $0.baseAddress!, $0.count) }
                    }
                    if type == .output || type == .redraw {
                        let start = off + 5
                        inbuf.withUnsafeBytes { raw in
                            var w = 0
                            while w < n {
                                let r = write(1, raw.baseAddress!.advanced(by: start + w), n - w)
                                if r > 0 { w += r } else if r < 0 && (errno == EAGAIN || errno == EINTR) { continue } else { break }
                            }
                        }
                        off += 5 + n
                        continue
                    }
                    let payload = Array(inbuf[(off + 5)..<(off + 5 + n)])
                    off += 5 + n
                    switch type {
                    case .exit:
                        let j = Wire.json(payload)
                        if let s = j["signal"] as? Int { return Int32(128 + s) }
                        return Int32(j["code"] as? Int ?? 0)
                    case .error:
                        let j = Wire.json(payload)
                        FileHandle.standardError.write(Data("roofd: \(j["message"] as? String ?? "error")\r\n".utf8))
                        return 1
                    default: break
                    }
                }
                if off > 0 { inbuf.removeFirst(off) }
            }
        }
    }
}
