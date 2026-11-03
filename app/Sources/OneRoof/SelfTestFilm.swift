import AppKit

/// LAB-2212 · Film the app's own windows in-process, for the launch demo: a timer draws every visible window of this
/// app into one frame of a screen region (back to front, where each window sits) and writes it as a JPEG named by the
/// milliseconds since the start. No Screen Recording permission is needed, and no other app's window can appear.
/// Self-test only (`film start x y w h fps` · `film stop` in a script); scripts/demo/edit.py turns the frames into video.
enum SelfTestFilm {
    private static var timer: Timer?
    private static var dir = ""
    private static var start = Date()
    private static var region = CGRect.zero   // screen points, top-left origin
    private static var pending = 0
    private static let encoder = DispatchQueue(label: "selftest.film", qos: .userInitiated)

    static func begin(dir: String, region: CGRect, fps: Double) {
        end()
        self.dir = dir
        self.region = region
        start = Date()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let t = Timer(timeInterval: 1 / max(1, fps), repeats: true) { _ in frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static func end() {
        timer?.invalidate()
        timer = nil
        encoder.sync {}
    }

    private static func frame() {
        guard pending < 4 else { return }   // the encoder is behind: skip this frame (the names keep the timing)
        let w = Int(region.width), h = Int(region.height)
        guard w > 0, h > 0, let top = NSScreen.screens.first?.frame.maxY,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let bottom = top - region.minY - region.height   // the region's bottom edge, AppKit coordinates
        for win in NSApp.orderedWindows.reversed() where win.isVisible && !win.isMiniaturized {
            guard let v = win.contentView?.superview ?? win.contentView else { continue }
            let f = win.frame
            let r = CGRect(x: f.minX - region.minX, y: f.minY - bottom, width: f.width, height: f.height)
            guard r.intersects(CGRect(x: 0, y: 0, width: w, height: h)), let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            if let cg = rep.cgImage { ctx.draw(cg, in: r) }
        }
        guard let img = ctx.makeImage() else { return }
        let path = (dir as NSString).appendingPathComponent(String(format: "f%08d.jpg", Int(Date().timeIntervalSince(start) * 1000)))
        pending += 1
        encoder.async {
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])?.write(to: URL(fileURLWithPath: path))
            DispatchQueue.main.async { pending -= 1 }
        }
    }
}
