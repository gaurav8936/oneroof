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
    /// LAB-1332: the playback position lives in its own small object; only the scrubber and the clocks observe it.
    /// Published here, it re-rendered every view of the player (the whole Learn page) twice a second while playing.
    let clock = PlaybackClock()
    static func clockText(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
    private(set) var elapsed: Double {
        get { clock.elapsed }
        set { if clock.elapsed != newValue { clock.elapsed = newValue } }
    }
    private(set) var duration: Double {
        get { clock.duration }
        set { if clock.duration != newValue { clock.duration = newValue } }
    }
    /// LAB-1233 · pages to play after this one (Learn › Radio: the rest of a band, a programme). Playing a page directly
    /// replaces it; stop() clears it.
    @Published private(set) var upNext: [QueuedPage] = []
    struct QueuedPage: Identifiable { var id: String; var title: String; var tracks: () -> [CourseTrack] }
    @Published var rate: Float = 1 { didSet { if playing { player?.rate = rate }; if save { defaults.set(rate, forKey: Self.rateKey) } } }

    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    private static let progressKey = "OneRoofLearnProgress", rateKey = "OneRoofLearnRate"
    private let defaults = Prefs.defaults
    private let save = !SelfTest.isActive          // tests never touch the owner's progress
    private var player: AVPlayer?
    /// ONEROOF_SELFTEST_PLAY / PLAYCARD=<…>@muted: a self-test plays a card silently (LAB-1281 frame checks).
    static let selfTestMuted = ["ONEROOF_SELFTEST_PLAY", "ONEROOF_SELFTEST_PLAYCARD"].contains { ProcessInfo.processInfo.environment[$0]?.hasSuffix("@muted") == true }
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
    func play(pageId: String, title: String, tracks: [CourseTrack], track: Int? = nil, upNext: [QueuedPage] = []) {
        guard !tracks.isEmpty else { return }
        self.upNext = upNext
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

    /// Skip to the next queued page (Radio's ⏭ when a band is queued); false when nothing is queued.
    @discardableResult func nextPage() -> Bool {
        while let n = upNext.first {
            let rest = Array(upNext.dropFirst())
            let t = n.tracks()
            if !t.isEmpty { play(pageId: n.id, title: n.title, tracks: t, track: 0, upNext: rest); return true }
            upNext = rest
        }
        return false
    }
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
        upNext = []
    }

    // MARK: Internals

    private func start(_ i: Int, at seconds: Double) {
        teardown()
        index = i
        let item = AVPlayerItem(url: URL(fileURLWithPath: tracks[i].path))
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        p.isMuted = Self.selfTestMuted
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

    private func finish(advance: Bool = true) {
        pause()
        if let id = pageId { progress[id] = nil; persist() }     // heard it all: next time starts at the beginning
        index = 0; elapsed = 0
        teardown()
        if advance, !upNext.isEmpty { DispatchQueue.main.async { [weak self] in self?.nextPage() } }
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
        if index == 0 && elapsed < 1 && progress[id] == nil { return }      // nothing heard yet (or just finished): no place to keep
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
    /// LAB-1629 · Learn: ⏮ ⏭ previous and next card (playing on) and back to the band the card came from; nil hides them.
    var onPrevCard: (() -> Void)? = nil
    var onNextCard: (() -> Void)? = nil
    var onBand: (() -> Void)? = nil
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
                // LAB-2116: the voice is AI-generated, said plainly on the player.
                Text(Narration.disclosure).font(.system(size: 10)).foregroundStyle(tokens.secondaryText.color).lineLimit(1)
                    .help(Narration.detail).accessibilityLabel(Narration.detail)
            }
            .frame(width: 260, alignment: .leading)
            HStack(spacing: 6) {
                if let onPrevCard { icon("backward.end.fill", "Previous card", onPrevCard) }
                icon("backward.fill", "Previous part") { player.previous() }
                icon(player.playing ? "pause.circle.fill" : "play.circle.fill", player.playing ? "Pause" : "Play", size: 24) { player.toggle() }
                icon("forward.fill", "Next part") { player.next() }
                if let onNextCard { icon("forward.end.fill", "Next card", onNextCard) }
            }
            if let onBand { icon("square.grid.2x2", "Back to the band", onBand) }
            PlaybackScrubber(player: player, clock: player.clock, tokens: tokens)
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
                // LAB-1233: the pages queued after this one (a band or a programme from Learn › Radio).
                if !player.upNext.isEmpty {
                    Text("UP NEXT · \(player.upNext.count)").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(tokens.text3.color).padding(.top, 8).padding(.bottom, 2)
                    ForEach(player.upNext.prefix(40)) { q in
                        Text(q.title).font(.system(size: 12)).foregroundStyle(tokens.text2.color).lineLimit(1).padding(.vertical, 2)
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 380, height: min(CGFloat(player.tracks.count + min(player.upNext.count, 40) + (player.upNext.isEmpty ? 0 : 2)) * 24 + 24, 420))
    }

    private func icon(_ name: String, _ help: String, size: CGFloat = 13, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: size)).foregroundStyle(tokens.text.color) }
            .buttonStyle(.plain).help(help)
    }

    private func clock(_ s: Double) -> String { CoursePlayer.clockText(s) }
}

/// A compact player in the title bar while something is loaded, so playback can be paused from any view.
struct MiniPlayer: View {
    @ObservedObject var player: CoursePlayer
    let openLearn: () -> Void

    var body: some View {
        if player.pageId != nil {
            HStack(spacing: 4) {
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).barHelp(player.playing ? "Pause" : "Play")   // in the toolbar: LAB-1236
                Button(action: openLearn) {
                    Text("\(player.pageTitle) · \(player.index + 1)/\(player.tracks.count)").font(.system(size: 11)).lineLimit(1).frame(maxWidth: 180)
                }
                .buttonStyle(.plain).barHelp("Open in Learn. " + Narration.disclosure)   // LAB-2116
                .accessibilityLabel("\(player.pageTitle), part \(player.index + 1) of \(player.tracks.count). \(Narration.detail) Open in Learn")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
        }
    }
}

/// LAB-1332 · where playback is: changes twice a second while playing.
final class PlaybackClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
}

/// LAB-1332 · the player bar's position and length, and its slider: the only part that redraws on each tick.
struct PlaybackScrubber: View {
    let player: CoursePlayer
    @ObservedObject var clock: PlaybackClock
    let tokens: ThemeTokens
    var body: some View {
        Text(CoursePlayer.clockText(clock.elapsed)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(tokens.secondaryText.color)
        Slider(value: Binding(get: { min(clock.elapsed, max(clock.duration, 1)) }, set: { player.seek($0) }),
               in: 0...max(clock.duration, 1))
            .controlSize(.small)
        Text(CoursePlayer.clockText(clock.duration)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(tokens.secondaryText.color)
    }
}

/// LAB-1332 · a view made from the playback position, redrawn on each tick without its parent.
struct PlaybackClockView<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    @ViewBuilder let content: (_ elapsed: Double) -> Content
    var body: some View { content(clock.elapsed) }
}
