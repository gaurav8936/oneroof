import AppKit
import SwiftUI
import OneRoofCore

// LAB-1233 · Learn in the v2 window, as drawn in the handover's `One Roof Learn.dc.html` (A12.2, 43-A12_2.jpg): one content
// header (breadcrumb · section on the left; on the right the card's actions, the mode control and "How do I…?" search), then
// Radio home, a band, a card station (Listen · Transcript · Skill file), Writing and the post reader, programmes and
// All cards. 1.9.2 (LAB-1274, owner): the control is exactly Radio · Writing · All cards; the Pages list and the course are
// gone (the classic window keeps its pages). Audio goes through CoursePlayer.

/// Where Learn is (one per window's Learn view; kept while the window lives).
final class LearnNav: ObservableObject {
    enum Place: String { case radio, band, card, post, writing, path, library }
    @Published var place: Place
    @Published var band = "loops"
    @Published var slug = "loops-first"
    @Published var tab = "listen"           // listen · transcript · skill
    @Published var scene = 0
    /// LAB-1621 · the card a roll-over opened: its page loads with `?autoplay=1` and starts playing (cleared once loaded).
    @Published var autoplay: String?
    @Published var post = ""
    @Published var path = "vibe-to-prod"
    @Published var query = ""
    @Published var lens = "loop"            // All cards: by band · by kind · by folder
    /// The selected block (by band / by kind), or "folder:<path from the deck root>" (by folder).
    @Published var libSel: String?
    /// By folder: the expanded folders (paths from the deck root).
    @Published var folderOpen: Set<String> = []
    /// LAB-1247: the band page scrolls to (and marks) this track when opened from an "On this band" chip.
    @Published var focusTrack: String?
    @Published var hover: String?
    @Published var toast = ""
    /// LAB-1274 · bumped to give the header's "How do I…?" field the keyboard (How Do I…? with no question).
    @Published var focusSearch = 0
    private var toastWork: DispatchWorkItem?
    private var sceneCache: [String: [DeckScene]] = [:]

    /// ONEROOF_SELFTEST_LEARNMODE: radio · band[:id[:track]] · card[:slug[:tab]] · writing · post[:slug] · path[:id] ·
    /// library (or map) · search:<text> · folder[:<path from the deck root>] (All cards › By folder, expanded down to it and
    /// selected) · radiokey:<band> / radiochip:<band>:<track> (Radio home, then a click on that band key / chip a moment later).
    init(spec: String? = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LEARNMODE"]) {
        let f = (spec ?? "radio").split(separator: ":", maxSplits: 2).map(String.init)
        switch f.first ?? "radio" {
        case "band": place = .band; if f.count > 1 { band = f[1] }; if f.count > 2 { focusTrack = f[2] }
        case "folder":
            place = .library; lens = "folder"
            if f.count > 1 {
                let rel = f.dropFirst().joined(separator: ":")
                folderOpen = Set(DeckFolders.ancestors(of: rel) + [rel]); libSel = "folder:" + rel
            }
        case "radiokey", "radiochip":
            place = .radio
            let route: LearnRadioRoute = f.first == "radiokey" ? .bandKey(f.count > 1 ? f[1] : "context")
                : .chip(band: f.count > 1 ? f[1] : "context", track: f.count > 2 ? f[2] : "vault")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in self?.follow(route, play: { _ in }) }
        case "card": place = .card; if f.count > 1 { slug = f[1] }; if f.count > 2 { tab = f[2] }
        case "writing": place = .writing
        case "post": place = .post; if f.count > 1 { post = f[1] }
        case "path": place = .path; if f.count > 1 { path = f[1] }
        case "library", "map": place = .library
        case "search": place = .library; query = f.count > 1 ? f[1] : ""
        default: place = .radio
        }
    }

    /// The mode control's segment for the current place.
    var mode: String {
        switch place {
        case .radio, .band, .card, .path: return "radio"
        case .writing, .post: return "writing"
        case .library: return "library"
        }
    }

    func go(_ p: Place) { place = p }
    func openCard(_ slug: String, tab: String = "listen", scene: Int = 0) {
        if place != .card { origin = place }          // LAB-1629: where "back to band" returns to
        self.slug = slug; self.tab = tab; self.scene = scene; place = .card
    }
    /// LAB-1629 · the place a card was opened from (Radio, a band, All cards …).
    private(set) var origin: Place = .radio

    /// LAB-1629 · back to band: the band page (or Radio) the card was opened from; from anywhere else, the card's band.
    func backToBand(_ slug: String, in deck: LearnDeck) {
        switch origin {
        case .radio: go(.radio)
        case .band: openBand(band)
        default: openBand(deck.band(of: slug).id)
        }
    }
    func openBand(_ id: String, track: String? = nil) { band = id; focusTrack = track; place = .band }

    /// LAB-1247: what a click on Radio home does (`LearnRadioRoute`): band keys and chips navigate, play controls play.
    func follow(_ route: LearnRadioRoute, play: (String) -> Void) {
        switch route {
        case .openBand(let id, let track): openBand(id, track: track)
        case .play(let k): slug = k; play(k)
        }
    }
    func openPost(_ slug: String) { post = slug; place = .post }

    func flash(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = "" }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }

    /// A card's scenes (spec.json), read once.
    func scenes(_ slug: String, _ deck: LearnDeck) -> [DeckScene] {
        if let s = sceneCache[slug] { return s }
        let s = DeckSpec.scenes(path: deck.specPath(slug), fallback: deck.cards[slug])
        sceneCache[slug] = s
        return s
    }

    /// A card's SKILL.md, read once (nil when the deck has no file for it).
    func skill(_ slug: String, _ deck: LearnDeck) -> DeckSkill? {
        if let s = skillCache[slug] { return s }
        let s = DeckSkill.load(deck.skillPath(slug))
        skillCache[slug] = s
        return s
    }
    private var skillCache: [String: DeckSkill?] = [:]
}

/// Playing deck cards through today's player.
struct LearnAudio {
    let deck: LearnDeck
    let player: CoursePlayer
    let nav: LearnNav

    /// The card the player has loaded, if it is one of the deck's.
    var playingSlug: String? { player.pageId.flatMap { deck.slug(forPage: $0) } }
    /// The card Radio is tuned to: what is playing, else the last card picked.
    var tuned: String { playingSlug ?? (deck.cards[nav.slug] != nil ? nav.slug : deck.dial.first ?? nav.slug) }

    /// Play `slug` from `scene`, then the cards in `then`, in order.
    func play(_ slug: String, scene: Int = 0, then rest: [String] = []) {
        guard let c = deck.cards[slug] else { return }
        let page = deck.htmlPath(slug), tracks = CourseAudio.tracks(page: page)
        guard !tracks.isEmpty else { nav.flash("\(c.title) has no narration in this build"); return }
        let queue = rest.filter { $0 != slug }.compactMap { k -> CoursePlayer.QueuedPage? in
            guard let q = deck.cards[k] else { return nil }
            let p = deck.htmlPath(k)
            return CoursePlayer.QueuedPage(id: p, title: q.title, tracks: { CourseAudio.tracks(page: p) })
        }
        player.play(pageId: page, title: c.title, tracks: tracks, track: min(max(0, scene), tracks.count - 1), upNext: queue)
    }

    /// Play the card, or pause / resume it when it is the one loaded.
    func toggle(_ slug: String, scene: Int = 0, then rest: [String] = []) {
        if playingSlug == slug { player.toggle() } else { play(slug, scene: scene, then: rest) }
    }

    /// The rest of `slug`'s band, from it on.
    func bandFrom(_ slug: String) -> [String] {
        let l = deck.lists[deck.band(of: slug).id] ?? []
        return l.firstIndex(of: slug).map { Array(l[$0...]) } ?? [slug]
    }
}

// MARK: - Header pieces

/// The design's small bordered buttons (Play page · Use in a session ▾ · Open in browser).
struct LearnChipStyle: ButtonStyle {
    @Environment(\.theme) private var t
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12)).foregroundStyle(t.text.color)
            .padding(.horizontal, 10).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(configuration.isPressed ? t.control.color : t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separatorStrong.color, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Radio · Writing · All cards (1.9.2: no Pages segment, LAB-1274).
struct LearnModeControl: View {
    @ObservedObject var nav: LearnNav
    @Environment(\.theme) private var t
    static let items = [("radio", "Radio"), ("writing", "Writing"), ("library", "All cards")]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.0) { id, label in
                let on = nav.mode == id
                Button {
                    switch id {
                    case "writing": nav.go(.writing)
                    case "library": nav.query = ""; nav.libSel = nil; nav.go(.library)
                    default: nav.go(.radio)
                    }
                } label: {
                    Text(label).font(.system(size: 12, weight: on ? .semibold : .regular)).foregroundStyle(t.text.color)
                        .padding(.horizontal, 12).frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? t.surface.color : Color.clear)
                            .shadow(color: on ? t.text.color.opacity(0.12) : .clear, radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.control.color))
    }
}

/// "How do I…? or search 156 cards": typing lists matching cards and posts (All cards › How do I…).
struct LearnSearchField: View {
    @ObservedObject var nav: LearnNav
    let total: Int
    @FocusState private var focused: Bool
    @Environment(\.theme) private var t
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(t.text3.color)
            TextField("How do I…? or search \(total) cards", text: Binding(get: { nav.query }, set: { v in
                nav.query = v
                if !v.isEmpty { nav.go(.library) } else if nav.place == .library { nav.go(.radio) }
            }))
            .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(t.text.color)
            .focused($focused)
        }
        .onChange(of: nav.focusSearch) { _, _ in focused = true }
        .padding(.horizontal, 8).frame(width: 220, height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separatorStrong.color, lineWidth: 1))
    }
}

/// The breadcrumb: earlier crumbs are links, the last is bold; then the section in small grey.
struct LearnCrumbs: View {
    struct Crumb { var label: String; var go: (() -> Void)? = nil }
    let crumbs: [Crumb]
    let section: String
    @Environment(\.theme) private var t
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                let last = i == crumbs.count - 1
                Button { c.go?() } label: {
                    Text(c.label).font(.system(size: 13, weight: last ? .bold : .regular))
                        .foregroundStyle(last ? t.text.color : t.text2.color).lineLimit(1)
                }
                .buttonStyle(.plain).disabled(c.go == nil)
                if !last { Text("›").font(.system(size: 13)).foregroundStyle(t.text3.color) }
            }
            Text(section).font(.system(size: 11)).foregroundStyle(t.text2.color).lineLimit(1).padding(.leading, 4)
        }
    }
}

/// The header row shared by every Learn place: left content, right actions.
struct LearnHeaderRow<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right
    @Environment(\.theme) private var t
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                left().layoutPriority(1)
                Spacer(minLength: 8)
                right()
            }
            .padding(.horizontal, 20).frame(height: 40)
            Rectangle().fill(t.separator.color).frame(height: 1)
        }
    }
}

/// A short label in capitals (the design's 11 pt kickers).
struct LearnKicker: View {
    let text: String
    var color: Color? = nil
    var size: CGFloat = 11
    @Environment(\.theme) private var t
    var body: some View {
        Text(text.uppercased()).font(.system(size: size, weight: .semibold)).tracking(size * 0.1).foregroundStyle(color ?? t.accentText.color)
    }
}

/// A column heading with a rule under it ("CHAPTERS", "PROGRAMMES · PATHS").
struct LearnRuleHeading<Trailing: View>: View {
    let text: String
    var size: CGFloat = 10
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.theme) private var t
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LearnKicker(text: text, color: t.text3.color, size: size)
                Spacer()
                trailing()
            }
            .padding(.bottom, size > 10 ? 8 : 5)
            Rectangle().fill(t.separatorStrong.color).frame(height: 1)
        }
    }
}
extension LearnRuleHeading where Trailing == EmptyView {
    init(text: String, size: CGFloat = 10) { self.init(text: text, size: size) { EmptyView() } }
}

/// The small round ▶ beside a card in a list.
struct LearnRoundPlay: View {
    let playing: Bool
    var size: CGFloat = 26
    let action: () -> Void
    @Environment(\.theme) private var t
    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: size * 0.33)).foregroundStyle(t.accent.color)
                .frame(width: size, height: size)
                .background(Circle().fill(t.surface.color))
                .overlay(Circle().strokeBorder(t.separatorStrong.color, lineWidth: 1))
        }
        .buttonStyle(.plain).help(playing ? "Pause" : "Play in One Roof")
    }
}

/// The accent capsule "▶ Play the band" / "▶ Play".
struct LearnPillPlay: View {
    let label: String
    var big = false
    let action: () -> Void
    @Environment(\.theme) private var t
    var body: some View {
        Button(action: action) {
            HStack(spacing: big ? 8 : 6) {
                Image(systemName: "play.fill").font(.system(size: big ? 10 : 9))
                Text(label).font(.system(size: big ? 13 : 12, weight: .semibold))
            }
            .foregroundStyle(t.onAccent.color)
            .padding(.horizontal, big ? 16 : 12).padding(.vertical, big ? 7 : 4)
            .background(Capsule().fill(t.accent.color))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Router

/// Radio, band, card, Writing, post, programme and All cards, below the shared header.
struct V2LearnRadio: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: CoursePlayer
    @ObservedObject var nav: LearnNav
    let deck: LearnDeck?
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    var body: some View {
        if let deck {
            let audio = LearnAudio(deck: deck, player: player, nav: nav)
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch nav.place {
                        case .band: LearnBandPage(nav: nav, player: player, audio: audio, posts: posts)
                        case .card: LearnCardStation(model: model, nav: nav, player: player, audio: audio, posts: posts)
                        case .post: LearnPostReader(nav: nav, player: player, audio: audio, posts: posts)
                        case .writing: LearnWritingPage(nav: nav, posts: posts)
                        case .path: LearnPathPage(nav: nav, player: player, audio: audio)
                        case .library: LearnLibraryPage(model: model, nav: nav, player: player, audio: audio, posts: posts)
                        default: LearnRadioHome(model: model, nav: nav, player: player, audio: audio, posts: posts)
                        }
                    }
                    .id("top")
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: nav.place) { _, _ in scroll(proxy) }
                .onChange(of: nav.focusTrack) { _, _ in if nav.place == .band { scroll(proxy) } }
                .onAppear { if nav.place == .band, nav.focusTrack != nil { scroll(proxy) } }
                .onChange(of: nav.slug) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 34)).foregroundStyle(t.text3.color)
                Text("The narrated deck is not in this build").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                Text("Radio, Writing and All cards read the Agentic Engineering deck bundled with release builds, and so do the skills. One Roof Help is under Help › One Roof Help.")
                    .font(.system(size: 12)).foregroundStyle(t.text2.color).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension V2LearnRadio {
    /// To the top, or (a band opened from a chip) to that track's group once it is laid out.
    func scroll(_ proxy: ScrollViewProxy) {
        if nav.place == .band, let tr = nav.focusTrack {
            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(LearnRadioRoute.anchor(track: tr), anchor: .top) } }
        } else {
            proxy.scrollTo("top", anchor: .top)
        }
    }
}

// MARK: - Radio home (L0)

struct LearnRadioHome: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t
    var deck: LearnDeck { audio.deck }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LearnKicker(text: "Agentic Engineering · Edition \(deck.version) · Ships with this build")
                Spacer()
                LearnKicker(text: "\(deck.count) cards" + (posts.isEmpty ? "" : " · \(posts.count) posts"), color: t.text3.color)
            }
            .padding(.top, 24)
            hero.padding(.top, 12)
            LearnRadioPanel(nav: nav, player: player, audio: audio).padding(.top, 28)
            LearnRadioLower(nav: nav, audio: audio, posts: posts).padding(.top, 40)
        }
        .padding(.horizontal, 40).padding(.bottom, 48)
        .frame(maxWidth: 1360, alignment: .leading)
    }

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 40) { headline.frame(maxWidth: 600, alignment: .leading); Spacer(minLength: 0); blurb }
            VStack(alignment: .leading, spacing: 16) { headline; blurb }
        }
    }

    private var headline: some View {
        (Text("Everything about building with agents, on one dial. ").foregroundColor(t.text.color)
         + Text("Tune in.").foregroundColor(t.accent.color))
            .font(.system(size: 60, weight: .bold)).tracking(-1.8).lineSpacing(-6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 420, alignment: .leading)
    }

    private var blurb: some View {
        Text("Short narrated cards, each one also a skill your agents run. It keeps playing while you work, and any card can go straight into a session.")
            .font(.system(size: 15)).lineSpacing(3).foregroundStyle(t.text2.color)
            .frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)
    }
}

/// The dial and player block: disc and keys, the dark now-playing display with the dial, four band presets and the knob.
struct LearnRadioPanel: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    @Environment(\.theme) private var t
    var deck: LearnDeck { audio.deck }

    var body: some View {
        let tuned = audio.tuned
        let band = deck.band(of: tuned)
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 16) {
                LearnDisc().frame(width: 210, height: 210)
                keys(tuned)
                LearnKicker(text: "Keeps playing while you work", color: t.text3.color, size: 10)
            }
            .frame(width: 210)
            VStack(alignment: .leading, spacing: 18) {
                LearnNowPlaying(nav: nav, player: player, audio: audio, tuned: tuned)
                presets(band, tuned)
                onThisBand(band)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.toolbar.color)
            .shadow(color: t.text.color.opacity(0.18), radius: 18, y: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
    }

    private func keys(_ tuned: String) -> some View {
        let d = t.display
        return HStack(spacing: 10) {
            LearnKey(fill: d.fill.color) {
                Image(systemName: player.playing && audio.playingSlug != nil ? "pause.fill" : "play.fill").font(.system(size: 13)).foregroundStyle(d.accent.color)
            } action: {
                if audio.playingSlug != nil { player.toggle() } else { audio.play(tuned, then: audio.bandFrom(tuned)) }
            }
            .help("Play or pause")
            LearnKey(fill: t.control.color) {
                Text(player.rate == 1 ? "1×" : String(format: "%g×", player.rate)).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text.color)
            } action: {
                let r = CoursePlayer.rates
                player.rate = r[((r.firstIndex(of: player.rate) ?? 1) + 1) % r.count]
            }
            .help("Speed 0.75–2×")
            LearnKey(fill: t.control.color) {
                Image(systemName: "forward.end").font(.system(size: 15)).foregroundStyle(t.text.color)
            } action: {
                let i = deck.dial.firstIndex(of: tuned) ?? -1
                let next = deck.dial[(i + 1) % max(1, deck.dial.count)]
                nav.slug = next
                if player.pageId != nil { audio.play(next, then: audio.bandFrom(next)) }
            }
            .help("Next card")
        }
    }

    private func presets(_ band: DeckBand, _ tuned: String) -> some View {
        HStack(spacing: 10) {
            ForEach(LearnDeck.bands) { b in
                let on = b.id == band.id
                let list = deck.lists[b.id] ?? []
                let d = t.display
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(b.n) · \(list.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(on ? d.accent.color : t.text3.color)
                    Text(b.title).font(.system(size: 17, weight: .bold)).foregroundStyle(on ? d.text.color : t.text.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? d.fill.color : t.control.color)
                    .shadow(color: d.keyEdge.color, radius: 0, y: on ? 1 : 3))
                .offset(y: on ? 2 : 0)
                .contentShape(Rectangle())
                // LAB-1247 (owner): a band key opens the band (pick what to hear there); it never starts playback.
                .onTapGesture { nav.follow(.bandKey(b.id)) { _ in } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open the \(b.title) band")
                .help("Open the \(b.title) band: \(b.sub)")
            }
            LearnKnob(fraction: deck.dial.count > 1 ? Double(deck.dial.firstIndex(of: tuned) ?? 0) / Double(deck.dial.count - 1) : 0)
                .frame(width: 84, height: 84).frame(width: 100, alignment: .trailing)
        }
    }

    private func onThisBand(_ band: DeckBand) -> some View {
        let list = deck.lists[band.id] ?? []
        return HStack(spacing: 8) {
            LearnKicker(text: "On this band", color: t.text3.color, size: 10)
            ForEach(band.tracks, id: \.self) { tr in
                let n = list.filter { deck.cards[$0]?.track == tr }.count
                if n > 0 {
                    // LAB-1247: a chip opens the band page at that track.
                    Button { nav.follow(.chip(band: band.id, track: tr)) { _ in } } label: {
                        (Text(LearnDeck.label(tr) + " ").foregroundColor(t.text.color) + Text("\(n)").foregroundColor(t.text3.color))
                            .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(t.separatorStrong.color, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Open the \(band.title) band at \(LearnDeck.label(tr))")
                }
            }
            Spacer(minLength: 8)
            Button { nav.openBand(band.id) } label: { Text("Open the \(band.title) band →").font(.system(size: 12)).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain)
        }
    }
}

/// The dark display: status, title, subtitle and chapter, progress, the dial.
struct LearnNowPlaying: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let tuned: String
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck, d = t.display
        let c = deck.cards[tuned]
        let band = deck.band(of: tuned)
        let scenes = nav.scenes(tuned, deck)
        let here = audio.playingSlug == tuned
        let idx = here ? min(player.index, max(0, scenes.count - 1)) : 0
        let total = Double(max(1, c?.estSeconds ?? 1))
        // Time on the card: earlier parts at the catalog's estimate per part, plus the clip being heard.
        let earlier = here ? total * Double(idx) / Double(max(1, player.tracks.count)) : 0
        let kicker = scenes.indices.contains(idx) ? scenes[idx].kicker : ""
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                (Text("● ").foregroundColor(d.accent.color)
                 + Text("\(here && player.playing ? "ON AIR" : "PAUSED") · \(band.n) \(band.title.uppercased()) · \(LearnDeck.label(c?.track ?? "").uppercased())"))
                Spacer()
                PlaybackClockView(clock: player.clock) { e in Text("\(LearnDeck.clock(here ? earlier + e : 0)) / \(LearnDeck.clock(total))") }   // LAB-1332
            }
            .font(.system(size: 11, design: .monospaced)).tracking(0.6).foregroundStyle(d.mute.color)
            Button { nav.openCard(tuned, scene: idx) } label: {
                Text(c?.title ?? tuned).font(.system(size: 34, weight: .bold)).tracking(-0.7).foregroundStyle(d.accent.color).lineLimit(1)
            }
            .buttonStyle(.plain).padding(.top, 8).help("Open the card")
            Text([c?.subtitle ?? "", "part \(idx + 1) of \(max(1, scenes.count))" + (kicker.isEmpty ? "" : ", " + kicker)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 15)).foregroundStyle(d.mute.color).lineLimit(1).padding(.top, 4)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(d.text.color.opacity(0.12))
                    PlaybackClockView(clock: player.clock) { e in   // LAB-1332: only the bar redraws on each tick
                        Rectangle().fill(d.accent.color).frame(width: g.size.width * min(1, (here ? earlier + e : 0) / total))
                    }
                }
            }
            .frame(height: 2).padding(.top, 14)
            LearnDial(deck: deck, tuned: tuned, only: nil) { k in
                nav.follow(.dial(k)) { audio.play($0, then: audio.bandFrom($0)) }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(d.fill.color))
    }
}

/// The dial: every card as a line (its height = its length), bands side by side, the tuned card marked by the needle.
/// Drawn from the catalog's card lengths (est_seconds); it is not an audio waveform. Click a line to tune in and play.
struct LearnDial: View {
    let deck: LearnDeck
    let tuned: String
    /// One band only (the band page), with track names under it.
    let only: String?
    let pick: (String) -> Void
    @Environment(\.theme) private var t

    private struct Mark { var slug: String; var x: CGFloat; var h: CGFloat; var on: Bool }
    private struct Label { var text: String; var x: CGFloat; var accent: Bool; var row = 0; var width: CGFloat? = nil; var hidden = false }

    /// The labels' type size at scale `s` (the band page's dial is drawn on a 1200-wide grid, Radio's on 680).
    private func fontSize(_ s: CGFloat) -> CGFloat { 10 * max(1, s * 0.9) }

    private func layout(_ w: CGFloat, _ s: CGFloat) -> ([Mark], [Label]) {
        let bands = only.map { id in LearnDeck.bands.filter { $0.id == id } } ?? LearnDeck.bands
        let gap: CGFloat = 14 * w / 680
        let seg = (w - CGFloat(bands.count - 1) * gap) / CGFloat(bands.count)
        let tunedBand = deck.partOf[tuned]
        var marks: [Mark] = [], labels: [Label] = []
        for (i, b) in bands.enumerated() {
            let x0 = CGFloat(i) * (seg + gap)
            let list = deck.lists[b.id] ?? []
            let step = seg / CGFloat(max(1, list.count - 1))
            let on = only != nil || b.id == tunedBand
            if only != nil { labels.append(Label(text: "START HERE", x: x0, accent: true)) }
            var lastTrack: String?
            for (j, k) in list.enumerated() {
                let x = x0 + CGFloat(j) * step
                let secs = CGFloat(deck.cards[k]?.estSeconds ?? 0)
                marks.append(Mark(slug: k, x: x, h: 8 + min(44, secs / 8), on: on))
                if only != nil, j >= b.key.filter({ deck.cards[$0] != nil }).count, let tr = deck.cards[k]?.track, tr != lastTrack {
                    labels.append(Label(text: LearnDeck.label(tr).uppercased(), x: x, accent: false)); lastTrack = tr
                }
            }
            if only == nil { labels.append(Label(text: "\(b.n) \(b.title.uppercased())", x: x0, accent: on)) }
        }
        // LAB-1272 · the band page names a track under its first card; a short track used to print its name over the next
        // one. Each label gets its text width: first row, else a second row, else shortened, else hidden (DialLabels).
        if only != nil {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize(s), weight: .regular)
            let widths = labels.map { ceil(($0.text as NSString).size(withAttributes: [.font: font]).width) }
            let placed = DialLabels.place(zip(labels, widths).map { (Double($0.x), Double($1)) }, total: Double(w), gap: Double(8 * s))
            for (i, p) in placed.enumerated() {
                labels[i].row = p.row; labels[i].hidden = p.hidden
                if p.truncated { labels[i].width = CGFloat(p.width) }
            }
        }
        return (marks, labels)
    }

    var body: some View {
        let d = t.display
        GeometryReader { g in
            let s = g.size.width / (only != nil ? 1200 : 680)
            let (marks, labels) = layout(g.size.width, s)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for m in marks {
                        let isT = m.slug == tuned
                        var p = Path(); p.move(to: CGPoint(x: m.x, y: 70 * s)); p.addLine(to: CGPoint(x: m.x, y: (70 - m.h) * s))
                        ctx.stroke(p, with: .color(isT ? d.accent.color : d.text.color.opacity(m.on ? 0.8 : 0.3)), lineWidth: 1.4)
                        if isT { ctx.fill(Path(CGRect(x: m.x - 1.5, y: 2 * s, width: 3, height: 68 * s)), with: .color(d.accent.color)) }
                    }
                }
                ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                    let y = 80 * s + CGFloat(l.row) * (fontSize(s) + 5)
                    if l.hidden {
                        // No room even shortened: the name is still there on hover, over its first card.
                        Color.clear.frame(width: 10, height: fontSize(s) + 2).contentShape(Rectangle())
                            .help(l.text.capitalized).offset(x: l.x - 5, y: y)
                    } else {
                        Text(l.text).font(.system(size: fontSize(s), design: .monospaced)).tracking(only != nil ? 0 : 1)
                            .foregroundStyle(l.accent ? d.accent.color : d.mute.color)
                            .lineLimit(1).truncationMode(.tail)
                            .fixedSize(horizontal: l.width == nil, vertical: true)
                            .frame(width: l.width, alignment: .leading)
                            .help(l.text.capitalized)
                            .offset(x: l.x, y: y)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                guard loc.y < 74 * s, let m = marks.min(by: { abs($0.x - loc.x) < abs($1.x - loc.x) }) else { return }
                pick(m.slug)
            }
            .help(deck.cards[tuned]?.title ?? "")
        }
        // The band page leaves room for a second row of track names (LAB-1272).
        .aspectRatio(only != nil ? 1200 / 112 : 680 / 98, contentMode: .fit)
    }
}

/// The dot-grid speaker disc.
struct LearnDisc: View {
    @Environment(\.theme) private var t
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: r * 2, height: r * 2)), with: .color(t.control.color))
            var y: CGFloat = 5.5
            while y < size.height {
                var x: CGFloat = 5.5
                while x < size.width {
                    let dx = x - c.x, dy = y - c.y
                    if dx * dx + dy * dy < (r - 3) * (r - 3) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(t.text.color.opacity(0.9)))
                    }
                    x += 11
                }
                y += 11
            }
        }
        .overlay(Circle().strokeBorder(t.text.color.opacity(0.08), lineWidth: 2).blur(radius: 2))
        .opacity(0.9)
    }
}

/// A keycap: 54×38 with the 3 pt edge under it.
struct LearnKey<Label: View>: View {
    let fill: Color
    @ViewBuilder var label: () -> Label
    let action: () -> Void
    @Environment(\.theme) private var t
    var body: some View {
        Button(action: action) {
            label().frame(width: 54, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill).shadow(color: t.display.keyEdge.color, radius: 0, y: 3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The tuning knob; its pointer turns from -135° to +135° across the dial.
struct LearnKnob: View {
    let fraction: Double
    @Environment(\.theme) private var t
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [t.surface.color, t.control.color], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60))
                .overlay(Circle().strokeBorder(t.separatorStrong.color, lineWidth: 1))
                .shadow(color: t.text.color.opacity(0.2), radius: 7, y: 6)
            RoundedRectangle(cornerRadius: 2).fill(t.text.color).frame(width: 4, height: 20)
                .offset(y: -24)
                .rotationEffect(.degrees(-135 + 270 * fraction))
        }
    }
}

/// Below the panel: the broadcast schedule (posts) and the programmes.
struct LearnRadioLower: View {
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 48) { schedule.frame(maxWidth: .infinity); programmes.frame(maxWidth: .infinity) }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnRuleHeading(text: "Broadcast schedule · Writing", size: 11) {
                Button { nav.go(.writing) } label: { Text("All writing →").font(.system(size: 12)).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
            }
            if posts.isEmpty {
                LearnNoPosts().padding(.top, 12)
            } else {
                ForEach(posts) { p in LearnPostRow(post: p, all: posts, compact: true) { nav.openPost(p.slug) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var programmes: some View {
        let deck = audio.deck
        return VStack(alignment: .leading, spacing: 0) {
            LearnRuleHeading(text: "Programmes · Paths", size: 11)
            ForEach(deck.paths, id: \.id) { pa in
                let ks = pa.slugs.filter { deck.cards[$0] != nil }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Button { nav.path = pa.id; nav.go(.path) } label: {
                            Text(pa.title).font(.system(size: 19, weight: .bold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        LearnPillPlay(label: "Play") { if let f = ks.first { audio.play(f, then: ks) }; nav.path = pa.id; nav.go(.path) }
                    }
                    Text(pa.why).font(.system(size: 13)).foregroundStyle(t.text2.color).padding(.top, 4)
                    Text(ks.compactMap { deck.cards[$0]?.title }.joined(separator: " → ")).font(.system(size: 12)).lineSpacing(3)
                        .foregroundStyle(t.text.color).padding(.top, 6)
                    Text("\(ks.count) CARDS · \(ks.reduce(0) { $0 + (deck.cards[$1]?.estSeconds ?? 0) } / 60) MIN · PLAYS IN ORDER")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(t.text3.color).padding(.top, 6)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What Writing shows when no Learn folder has posts (the app ships none).
/// LAB-1251: posts come from the blog hub, so this says what the hub did: still loading, answered with no
/// posts, or could not be reached with no copy saved on this Mac (then: try again).
struct LearnNoPosts: View {
    @ObservedObject private var blog = LearnBlogFeed.shared
    @Environment(\.theme) private var t
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.message(blog.state)).font(.system(size: 12.5)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            if case .offline = blog.state {
                Button { blog.refresh(force: true) } label: { Text("Try again").font(.system(size: 12.5)).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func message(_ s: LearnBlogFeed.State) -> String {
        switch s {
        case .idle, .loading: return "Loading posts from the \(BlogHub.name)…"
        case .reached: return "The \(BlogHub.name) has no posts yet."
        case .offline(let why):
            return "Can't reach the \(BlogHub.name) (\(why)) and no copy is saved on this Mac yet. Posts show here once One Roof is online."
        }
    }
}

/// Where Writing's posts come from: "From the <Site> blog · updated 10:42", or the saved copy while offline.
struct LearnPostsSource: View {
    @ObservedObject private var blog = LearnBlogFeed.shared
    let posts: [LearnPost]
    @Environment(\.theme) private var t
    var body: some View {
        let hub = posts.contains { !$0.source.isEmpty }
        let local = posts.contains { $0.source.isEmpty }
        HStack(spacing: 10) {
            Text(text(hub: hub, local: local)).font(.system(size: 12)).foregroundStyle(t.text3.color)
            if case .offline = blog.state {
                Button { blog.refresh(force: true) } label: { Text("Try again").font(.system(size: 12)).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func text(hub: Bool, local: Bool) -> String {
        var parts: [String] = []
        if hub {
            switch blog.state {
            case .offline: parts.append("Offline · the copy saved " + Self.when(blog.savedAt))
            case .loading, .idle: parts.append("From the \(BlogHub.name) · checking for new posts…")
            case .reached: parts.append("From the \(BlogHub.name) · updated " + Self.when(blog.savedAt))
            }
        }
        if local { parts.append("plus your Learn folders") }
        return parts.joined(separator: " · ")
    }

    static func when(_ d: Date?) -> String {
        guard let d else { return "earlier" }
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A post in the broadcast schedule (Radio home) or in Writing.
struct LearnPostRow: View {
    let post: LearnPost
    let all: [LearnPost]
    var compact = false
    let go: () -> Void
    @Environment(\.theme) private var t
    @State private var hover = false

    var body: some View {
        let series = all.filter { $0.series == "Agentic engineering" }
        let part = series.firstIndex(of: post).map { "Series · Part \($0 + 1)" } ?? "Field notes"
        let st = LearnPosts.state(post, in: all, today: LearnPostRow.today)
        let bands = LearnDeck.bands.filter { $0.posts.contains(post.slug) }.map(\.title)
        Button(action: go) {
            HStack(alignment: .firstTextBaseline, spacing: compact ? 14 : 20) {
                Text(LearnPostRow.day(post.date)).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text2.color).frame(width: compact ? 96 : 110, alignment: .leading)
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    Text(post.title).font(.system(size: compact ? 15 : 17, weight: compact ? .semibold : .bold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                    if compact {
                        Text("\(part) · \(bands.isEmpty ? "all four bands" : bands.joined(separator: ", ")) · \(post.minutes) min read")
                            .font(.system(size: 11)).foregroundStyle(t.text3.color)
                    } else if !post.subtitle.isEmpty {
                        Text(post.subtitle).font(.system(size: 13)).foregroundStyle(t.text2.color).multilineTextAlignment(.leading).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(st.label).font(.system(size: compact ? 10 : 11, design: .monospaced)).foregroundStyle(st.isNext ? t.accentText.color : t.text3.color)
                    if !compact { Text("\(post.minutes) min read").font(.system(size: 11)).foregroundStyle(t.text3.color) }
                }
                .frame(width: compact ? 100 : 120, alignment: .trailing)
            }
            .padding(.horizontal, compact ? 10 : 8).padding(.vertical, compact ? 11 : 14)
            .background(RoundedRectangle(cornerRadius: 6).fill(st.isNext || hover ? t.selection.color : Color.clear))
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    static var today: String { day0.string(from: Date()) }
    private static let day0: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    /// "Sat 24 Oct".
    static func day(_ s: String) -> String {
        guard let d = LearnPosts.day(s) else { return s }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}
