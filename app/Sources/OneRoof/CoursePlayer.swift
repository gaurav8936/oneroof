import AVFoundation
import SwiftUI
import OneRoofCore

/// Learn's audio player: plays a page's narration as a queue, at the speed the owner picks, carries on
/// while the owner works in the terminals, and remembers where each page was left off.
final class CoursePlayer: ObservableObject {
    @Published private(set) var pageId: String?
    @Published private(set) var pageTitle = ""
    @Published private(set) var tracks: [CourseTrack] = []
    @Published private(set) var index = 0
    @Published private(set) var playing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1 { didSet { if playing { player?.rate = rate }; if save { defaults.set(rate, forKey: Self.rateKey) } } }

    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    private static let progressKey = "OneRoofLearnProgress", rateKey = "OneRoofLearnRate"
    private let defaults = Prefs.defaults
    private let save = !SelfTest.isActive          // tests never touch the owner's progress
    private var player: AVPlayer?
    private var tick: Any?
    private var endObserver: NSObjectProtocol?
    private var progress: [String: CourseProgress] = [:]
    private var lastSaved = Date.distantPast

    init() {
        if save, let d = defaults.data(forKey: Self.progressKey),
           let p = try? JSONDecoder().decode([String: CourseProgress].self, from: d) { progress = p }
        if save, defaults.object(forKey: Self.rateKey) != nil { rate = defaults.float(forKey: Self.rateKey) }
    }

    var current: CourseTrack? { tracks.indices.contains(index) ? tracks[index] : nil }

    /// Where `pageId` was left off, if anywhere.
    func saved(_ pageId: String) -> CourseProgress? { progress[pageId] }

    /// Load a page's tracks and play, continuing where it was left off (or from `track` when given).
    func play(pageId: String, title: String, tracks: [CourseTrack], track: Int? = nil) {
        guard !tracks.isEmpty else { return }
        if self.pageId != pageId || self.tracks != tracks {
            remember()
            self.pageId = pageId; pageTitle = title; self.tracks = tracks
        }
        let resume = track == nil ? progress[pageId] : nil
        start(track ?? min(resume?.track ?? 0, tracks.count - 1), at: resume?.seconds ?? 0)
    }

    func toggle() { playing ? pause() : resume() }

    func resume() {
        guard let player else { if pageId != nil { start(index, at: elapsed) }; return }
        player.rate = rate
        playing = true
    }

    func pause() {
        player?.pause()
        playing = false
        remember()
    }

    func next() { if index + 1 < tracks.count { start(index + 1, at: 0) } else { finish() } }
    func previous() { elapsed > 3 || index == 0 ? seek(0) : start(index - 1, at: 0) }

    func seek(_ seconds: Double) {
        player?.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        elapsed = max(0, seconds)
    }

    /// Stop and forget the queue (the page's place is kept).
    func stop() {
        pause()
        teardown()
        pageId = nil; tracks = []; index = 0; elapsed = 0; duration = 0
    }

    // MARK: Internals

    private func start(_ i: Int, at seconds: Double) {
        teardown()
        index = i
        let item = AVPlayerItem(url: URL(fileURLWithPath: tracks[i].path))
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        player = p
        elapsed = seconds; duration = 0
        if seconds > 0 { p.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        tick = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            self.elapsed = t.seconds
            if let d = p.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            if Date().timeIntervalSince(self.lastSaved) > 5 { self.remember() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.next()
        }
        p.rate = rate
        playing = true
    }

    private func finish() {
        pause()
        if let id = pageId { progress[id] = nil; persist() }     // heard it all: next time starts at the beginning
        index = 0; elapsed = 0
        teardown()
    }

    private func teardown() {
        if let tick { player?.removeTimeObserver(tick) }
        tick = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
    }

    private func remember() {
        guard let id = pageId, current != nil else { return }
        progress[id] = CourseProgress(track: index, seconds: elapsed)
        persist()
    }

    private func persist() {
        lastSaved = Date()
        guard save, let d = try? JSONEncoder().encode(progress) else { return }
        defaults.set(d, forKey: Self.progressKey)
    }
}

/// The player controls: title, part n of m, previous / play / next, a scrubber, speed and the queue.
struct PlayerBar: View {
    @ObservedObject var player: CoursePlayer
    let tokens: ThemeTokens
    var onOpenPage: (() -> Void)? = nil
    @State private var showQueue = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Button { onOpenPage?() } label: {
                    Text(player.pageTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.text.color).lineLimit(1)
                }
                .buttonStyle(.plain).disabled(onOpenPage == nil)
                Text("Part \(player.index + 1) of \(player.tracks.count) · \(player.current?.title ?? "")")
                    .font(.system(size: 10.5)).foregroundStyle(tokens.secondaryText.color).lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            HStack(spacing: 6) {
                icon("backward.fill", "Previous part") { player.previous() }
                icon(player.playing ? "pause.circle.fill" : "play.circle.fill", player.playing ? "Pause" : "Play", size: 24) { player.toggle() }
                icon("forward.fill", "Next part") { player.next() }
            }
            Text(clock(player.elapsed)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(tokens.secondaryText.color)
            Slider(value: Binding(get: { min(player.elapsed, max(player.duration, 1)) }, set: { player.seek($0) }),
                   in: 0...max(player.duration, 1))
                .controlSize(.small)
            Text(clock(player.duration)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(tokens.secondaryText.color)
            Picker("", selection: $player.rate) {
                ForEach(CoursePlayer.rates, id: \.self) { r in Text(r == 1 ? "1×" : String(format: "%g×", r)).tag(r) }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize().help("Speed")
            icon("list.bullet", "Queue") { showQueue = true }
                .popover(isPresented: $showQueue, arrowEdge: .top) { queue }
            icon("xmark", "Stop") { player.stop() }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(tokens.surface.color)
    }

    private var queue: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(player.tracks.enumerated()), id: \.offset) { i, t in
                    Button {
                        if let id = player.pageId { player.play(pageId: id, title: player.pageTitle, tracks: player.tracks, track: i) }
                    } label: {
                        HStack {
                            Image(systemName: i == player.index ? "speaker.wave.2.fill" : "circle").font(.system(size: 9)).frame(width: 14)
                            Text("\(i + 1). \(t.title)").font(.system(size: 12, weight: i == player.index ? .semibold : .regular)).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.vertical, 3)
                }
            }
            .padding(10)
        }
        .frame(width: 380, height: min(CGFloat(player.tracks.count) * 24 + 24, 420))
    }

    private func icon(_ name: String, _ help: String, size: CGFloat = 13, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: size)).foregroundStyle(tokens.text.color) }
            .buttonStyle(.plain).help(help)
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// A compact player in the title bar while something is loaded, so playback can be paused from any view.
struct MiniPlayer: View {
    @ObservedObject var player: CoursePlayer
    let openLearn: () -> Void

    var body: some View {
        if player.pageId != nil {
            HStack(spacing: 4) {
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).help(player.playing ? "Pause" : "Play")
                Button(action: openLearn) {
                    Text("\(player.pageTitle) · \(player.index + 1)/\(player.tracks.count)").font(.system(size: 11)).lineLimit(1).frame(maxWidth: 180)
                }
                .buttonStyle(.plain).help("Open in Learn")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
        }
    }
}
