// LAB-2212 · Record one app's windows (and nothing else on the screen) to an .mp4, for the launch demo.
// ScreenCaptureKit with a filter that includes only the app with <pid>: other apps' windows that cover it are not
// filmed, so the owner can keep working while it records. Stops on SIGINT / SIGTERM, or after <seconds>.
//
//   swift scripts/demo/record.swift <pid> <out.mp4> <x> <y> <w> <h> [seconds]
//   x y w h: the screen region in points, top-left origin (the main display); the video is w×h pixels at 30 fps.
// Needs Screen Recording permission for the app that runs it. A dev tool; never shipped in the app.
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

let a = CommandLine.arguments
guard a.count >= 7, let pid = pid_t(a[1]), let x = Double(a[3]), let y = Double(a[4]), let w = Int(a[5]), let h = Int(a[6]) else {
    FileHandle.standardError.write("usage: record.swift <pid> <out.mp4> <x> <y> <w> <h> [seconds]\n".data(using: .utf8)!)
    exit(64)
}
let outURL = URL(fileURLWithPath: a[2])
let seconds = a.count > 7 ? Double(a[7]) : nil
try? FileManager.default.removeItem(at: outURL)

final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0
    let q = DispatchQueue(label: "rec")

    init(url: URL, w: Int, h: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoExpectedSourceFrameRateKey: 30,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        // Only complete frames (idle frames carry no image).
        guard let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = att.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            started = true
            print("recording started \(Date().timeIntervalSince1970)")
            fflush(stdout)
        }
        if input.isReadyForMoreMediaData { input.append(sb); frames += 1 }
    }

    func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}

let sema = DispatchSemaphore(value: 0)
var recorder: Recorder?
var stream: SCStream?

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.processID == pid }) else {
            FileHandle.standardError.write("record: no app with pid \(pid) (Screen Recording permission?)\n".data(using: .utf8)!)
            exit(2)
        }
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { exit(2) }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = CGRect(x: x, y: y, width: Double(w), height: Double(h))
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.showsCursor = false
        cfg.queueDepth = 6
        cfg.backgroundColor = .black
        let r = try Recorder(url: outURL, w: w, h: h)
        let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try s.addStreamOutput(r, type: .screen, sampleHandlerQueue: r.q)
        try await s.startCapture()
        recorder = r
        stream = s
    } catch {
        FileHandle.standardError.write("record: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

func stop() {
    Task {
        try? await stream?.stopCapture()
        await recorder?.finish()
        print("recording stopped \(Date().timeIntervalSince1970) frames \(recorder?.frames ?? 0)")
        fflush(stdout)
        sema.signal()
    }
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigs = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { stop() }
    src.resume()
    return src
}
if let seconds { DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { stop() } }
DispatchQueue.global().async { sema.wait(); exit(0) }
dispatchMain()
