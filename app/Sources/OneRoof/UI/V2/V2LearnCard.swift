import AppKit
import SwiftUI
import OneRoofCore

// LAB-1233 · Learn › the card station (L2): Listen, Transcript and the card's Skill file, with triggers, pairs, posts and
// what is next on the band down the right.
// LAB-1305 (1.9.5, owner: Learn has nothing original, it only organises the deck): Listen is the card's own page from the
// deck (`LearnCardPage`), the same page the repository and the other sites show, with its diagram, sections menu, step pills
// and narration player. Its sections menu replaces the native Chapters list. The native scene view (`LearnListen`) and
// the Chapters list are kept only as the fallback for a card the deck has no HTML page for.

struct LearnCardStation: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    /// LAB-1619 · the right rail folds away (remembered); folded, the card's page takes the whole width.
    @AppStorage("learn.cardRailFolded") private var railStored = false
    /// ONEROOF_SELFTEST_RAILFOLDED=1 shows the rail folded without writing the setting.
    private var railFolded: Bool { railStored || ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_RAILFOLDED"] == "1" }
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        if let c = deck.cards[nav.slug] {
            let scenes = nav.scenes(c.slug, deck)
            let here = audio.playingSlug == c.slug
            let idx = max(0, min(scenes.count - 1, here ? player.index : nav.scene))
            let page = LearnCardPage.source(c.slug, in: deck)
            // LAB-1619 (owner, 10-29): the stage fills the window and grows with it, in width and height (no fixed max
            // width); the rail is narrower and folds away.
            HStack(alignment: .top, spacing: railFolded ? 0 : 24) {
                main(c, scenes, idx, here, page).frame(maxWidth: .infinity)
                if !railFolded {
                    LearnCardSide(nav: nav, player: player, audio: audio, posts: posts, card: c, scenes: scenes, idx: idx, here: here,
                                  chapters: page == nil).frame(width: LearnCardStation.railWidth)
                }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func main(_ c: DeckCard, _ scenes: [DeckScene], _ idx: Int, _ here: Bool, _ page: LearnCardPage.Source?) -> some View {
        let b = audio.deck.band(of: c.slug)
        let narrated = here || FileManager.default.fileExists(atPath: (audio.deck.htmlPath(c.slug) as NSString).deletingPathExtension + "_audio")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Button { nav.openBand(b.id) } label: { LearnKicker(text: "Band \(b.n) · \(b.title) · \(LearnDeck.label(c.track))") }.buttonStyle(.plain)
                Spacer()
                Text("\(c.scenes) scenes · \(LearnDeck.minutes(c.estSeconds))" + (narrated ? " · narration bundled" : ""))
                    .font(.system(size: 12)).foregroundStyle(t.text3.color)
            }
            // LAB-1305: on Listen the card's own page carries its title and subtitle, so they are not drawn twice.
            if page == nil || nav.tab == "transcript" || nav.tab == "skill" {
                Text(c.title).font(.system(size: 48, weight: .bold)).tracking(-1.4).foregroundStyle(t.text.color).padding(.top, 6).padding(.bottom, 6)
                Text(c.subtitle.isEmpty ? c.description : c.subtitle).font(.system(size: 17)).foregroundStyle(t.text2.color).padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Spacer().frame(height: 12)
            }
            tabs.padding(.bottom, 16)
            switch nav.tab {
            case "transcript": LearnTranscript(nav: nav, audio: audio, card: c, scenes: scenes, idx: idx)
            case "skill": LearnSkillFile(nav: nav, audio: audio, card: c)
            default:
                if let page { LearnCardWeb(nav: nav, player: player, audio: audio, card: c, source: page, autoAdvance: model.settings.learnAutoAdvance) }
                // Fallback: the deck has no HTML page for this card, so the scenes from its spec.json are drawn natively.
                else { LearnListen(nav: nav, player: player, audio: audio, card: c, scenes: scenes, idx: idx, here: here) }
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach([("listen", "Listen"), ("transcript", "Transcript"), ("skill", "Skill file")], id: \.0) { id, label in
                    let on = nav.tab == id
                    Button { nav.tab = id } label: {
                        Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? t.text.color : t.text2.color)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(on ? t.accent.color : Color.clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.15)) { railStored = !railFolded } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sidebar.right").font(.system(size: 12))
                        Text(railFolded ? "Show side panel" : "Hide side panel").font(.system(size: 12))
                    }
                    .foregroundStyle(t.text2.color).padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(railFolded ? "Show Say it in a session, Pairs with, Read about it and Next on the band" : "Hide the side panel: the card takes the whole width")
                .accessibilityLabel(railFolded ? "Show side panel" : "Hide side panel")
            }
            Rectangle().fill(t.separatorStrong.color).frame(height: 1)
        }
    }

    /// LAB-1619 · the rail's width (was 320).
    static let railWidth: CGFloat = 248
}

/// LAB-1305 · Listen: the card's own page from the deck, as the repository and the other sites show it. Links: anchors stay in
/// the page, another card's page opens that card here, other deck pages load in place, web links open in the browser
/// (WebPage). Audio never doubles: the page starting its narration pauses One Roof's player, and One Roof's player
/// starting pauses the page; while One Roof plays this card the page shows the scene being heard.
struct LearnCardWeb: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let card: DeckCard
    let source: LearnCardPage.Source
    /// LAB-1621 · Settings › Learn › Auto-advance to the next card.
    var autoAdvance = true
    @State private var bridge = WebPageBridge()
    /// LAB-1621 · the roll-over countdown: the next card and the seconds left (nil = none running).
    @State private var rollNext: String?
    @State private var rollLeft = 0
    @State private var rollTask: Task<Void, Never>?
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck, player = player, nav = nav, slug = card.slug
        VStack(spacing: 10) {
            // The countdown sits above the page (WebKit draws out of process, so nothing is layered over the page itself).
            if let n = rollNext { countdown(n).transition(.opacity) }
            WebPage(path: source.page, root: source.readRoot, blocked: { LearnExclusions.isExcluded($0) },
                    pageScript: LearnExclusions.hideLinksScript,
                    startScript: LearnCardPage.bridgeScript(muted: CoursePlayer.selfTestMuted) + "\n" + LearnRollover.escapeScript(media: LearnCardPage.handler),
                    onMessage: { kind in
                        if kind == "ready" { follow(); startAutoplay(); selfTestClick(); selfTestEnded(); return }
                        if kind == "escape" { cancelRollover(); return }
                        cancelRollover()                            // the page started playing again: stay on this card
                        if player.playing { player.pause() }       // the page started its own narration
                    },
                    onLocalLink: { path in
                        guard let k = LearnCardPage.linkedCard(path, in: deck), k != slug else { return false }
                        nav.openCard(k); return true
                    },
                    bridge: bridge,
                    onCardMessage: { body in cardEnded(body) },
                    autoplay: nav.autoplay == slug)
                .id(source.page)
                // LAB-1619: the page and its own player bar fill the height under the kicker and tabs (was h - 150).
                .containerRelativeFrame(.vertical) { h, _ in max(480, h - 112 - (rollNext == nil ? 0 : 54)) }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
        }
        .onChange(of: player.playing) { _, on in if on { cancelRollover(); bridge.run(LearnCardPage.pauseScript); follow() } }
        .onChange(of: player.index) { _, _ in if player.playing { follow() } }
        .onDisappear { cancelRollover() }
    }

    // MARK: Roll-over (LAB-1621)

    /// "Next: <title> in 3…" with Stay (Esc) and Play now.
    private func countdown(_ next: String) -> some View {
        let title = audio.deck.cards[next]?.title ?? next
        return HStack(spacing: 12) {
            Image(systemName: "forward.end.fill").font(.system(size: 12)).foregroundStyle(t.accentText.color)
            Text(LearnRollover.label(title: title, left: rollLeft)).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.text.color)
                .monospacedDigit().lineLimit(1)
            Button { cancelRollover() } label: { Text("Stay").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(LearnChipStyle()).keyboardShortcut(.cancelAction).help("Stay on this card (Esc)")
            Button { go(next) } label: { Text("Play now").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(LearnChipStyle()).help("Open \(title) now")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.selection.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.accent.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LearnRollover.label(title: title, left: rollLeft))
    }

    /// LAB-1629 · the page's player bar asks for ⏮ ⏭ or back to band; the next and previous cards play on when the page
    /// was playing.
    private func cardNav(_ r: LearnRollover.NavRequest) {
        cancelRollover()
        let deck = audio.deck, slug = card.slug
        switch r.to {
        case .band: nav.backToBand(slug, in: deck)
        case .prevCard, .nextCard:
            guard let k = r.to == .nextCard ? LearnRollover.next(after: slug, in: deck) : LearnRollover.previous(before: slug, in: deck) else { return }
            let open = { (play: Bool) in
                if play { nav.autoplay = k }
                nav.openCard(k)
            }
            if let p = r.playing { open(p) } else { bridge.ask(LearnRollover.isPlayingScript) { open($0) } }
        }
    }

    /// The page says it ended: count down to the next card (when auto-advance is on and there is one).
    private func cardEnded(_ body: Any) {
        if let r = LearnRollover.navRequest(body, fallback: card.slug) { cardNav(r); return }
        guard autoAdvance, rollNext == nil, LearnRollover.endedCard(body, fallback: card.slug) == card.slug,
              let next = LearnRollover.next(after: card.slug, in: audio.deck) else { return }
        rollNext = next; rollLeft = LearnRollover.seconds
        rollTask?.cancel()
        rollTask = Task { @MainActor in
            for left in stride(from: LearnRollover.seconds, to: 0, by: -1) {
                rollLeft = left
                try? await Task.sleep(nanoseconds: UInt64(LearnCardWeb.tick * 1_000_000_000))
                if Task.isCancelled || rollNext != next { return }
            }
            go(next)
        }
    }

    private func cancelRollover() {
        rollTask?.cancel(); rollTask = nil
        if rollNext != nil { rollNext = nil }
    }

    /// Open the next card; its page starts playing by itself (`?autoplay=1`, then the fallback once loaded).
    private func go(_ next: String) {
        cancelRollover()
        nav.autoplay = next
        nav.openCard(next)
    }

    /// The card a roll-over opened has loaded: make sure it plays, then forget the flag.
    private func startAutoplay() {
        guard nav.autoplay == card.slug else { return }
        nav.autoplay = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { bridge.run(LearnRollover.playScript) }
    }

    /// ONEROOF_SELFTEST_CARDENDED=<seconds>: once, that long after the first card page loads, the page posts its end
    /// (as a card played to its end does), to capture the countdown and the roll-over.
    private func selfTestEnded() {
        guard let s = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_CARDENDED"], !LearnCardWeb.selfTestEndedFired else { return }
        LearnCardWeb.selfTestEndedFired = true
        let js = LearnRollover.endedScript(card: card.slug)
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(s) ?? 1)) { bridge.run(js) }
    }
    @MainActor private static var selfTestEndedFired = false
    /// Seconds per countdown step: 1, or ONEROOF_SELFTEST_ROLLTICK (self-tests slow it down to capture it).
    private static let tick: Double = Double(ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_ROLLTICK"] ?? "") ?? 1

    /// Show the scene One Roof's player is on, in the page (only while it plays this card).
    private func follow() {
        guard audio.playingSlug == card.slug, player.playing else { return }
        let i = player.index, n = player.tracks.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { bridge.run(LearnCardPage.showSceneScript(i, tracks: n)) }
    }

    /// ONEROOF_SELFTEST_PAGECLICK=<element id>[@<seconds>]: click that element of the card page once it has loaded
    /// (e.g. playAll, to check the page's own narration pauses One Roof's player).
    /// Several clicks: "playAll@1,nextCard@4" (seconds after the first card page loaded; only that first page, so a click
    /// that opens another card does not repeat on it).
    private func selfTestClick() {
        guard let spec = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_PAGECLICK"], !LearnCardWeb.selfTestClicked else { return }
        LearnCardWeb.selfTestClicked = true
        let bridge = bridge
        for one in spec.split(separator: ",") {
            let f = one.split(separator: "@").map(String.init), id = f.first ?? ""
            let js = "(function(){ var e = document.getElementById('\(id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })'); if (e) e.click(); })();"
            DispatchQueue.main.asyncAfter(deadline: .now() + (f.count > 1 ? Double(f[1]) ?? 1 : 1)) { bridge.run(js) }
        }
    }
    @MainActor private static var selfTestClicked = false
}

/// Fallback Listen for a card without a page (LAB-1305): the scene's panel (section, kicker, heading, the section's diagram with this scene's nodes lit, the lede and
/// points), scene dots, and the narration text under it.
struct LearnListen: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    let here: Bool
    @Environment(\.theme) private var t

    var body: some View {
        let s = scenes.indices.contains(idx) ? scenes[idx] : nil
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    LearnKicker(text: "Scene \(idx + 1) of \(scenes.count) · \(s?.section ?? "")", color: t.text3.color)
                    Spacer()
                    PlaybackClockView(clock: player.clock) { _ in LearnKicker(text: live, color: here ? t.accentText.color : t.text3.color) }   // LAB-1332
                }
                if let s {
                    Text(s.kicker).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.accentText.color).padding(.top, 18)
                    Text(s.heading).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(t.text.color)
                        .frame(maxWidth: 760, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    blocks(s).padding(.top, 20)
                }
                Spacer(minLength: 0)
                controls.padding(.top, 22)
            }
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.toolbar.color))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
            if let s, !s.narration.isEmpty {
                Text(s.narration).font(.system(size: 15)).lineSpacing(5).foregroundStyle(t.text.color)
                    .frame(maxWidth: 780, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                    .textSelection(.enabled)
            }
        }
    }

    private var live: String {
        if here { return player.playing ? "● Playing · \(LearnDeck.clock(player.elapsed)) / \(LearnDeck.clock(player.duration))" : "Paused" }
        return ""
    }

    @ViewBuilder private func blocks(_ s: DeckScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !s.nodes.isEmpty {
                LearnFlow(spacing: 10) {
                    ForEach(Array(s.nodes.enumerated()), id: \.offset) { _, n in
                        let lit = s.highlight.contains(n.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                            if !n.sub.isEmpty { Text(n.sub).font(.system(size: 12)).foregroundStyle(t.text2.color) }
                        }
                        .frame(minWidth: 150, maxWidth: 260, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? t.selection.color : t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(lit ? t.accent.color : t.separator.color, lineWidth: 1))
                    }
                }
            }
            if !s.lede.isEmpty || !s.points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !s.lede.isEmpty { Text(s.lede).font(.system(size: 14, weight: .medium)).foregroundStyle(t.text.color) }
                    ForEach(s.points, id: \.self) { p in Text("· " + p).font(.system(size: 13)).foregroundStyle(t.text2.color) }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(t.accent.color).frame(width: 2) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            circle("chevron.left") { here ? player.previous() : (nav.scene = max(0, idx - 1)) }
            HStack(spacing: 4) {
                ForEach(0..<scenes.count, id: \.self) { i in
                    Button { here ? audio.play(card.slug, scene: i, then: audio.bandFrom(card.slug)) : (nav.scene = i) } label: {
                        RoundedRectangle(cornerRadius: 3).fill(i == idx ? t.accent.color : i < idx ? t.separatorStrong.color : t.control.color)
                            .frame(height: 5).frame(maxWidth: .infinity).contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain).help(scenes[i].kicker)
                }
            }
            circle("chevron.right") { here ? player.next() : (nav.scene = min(scenes.count - 1, idx + 1)) }
        }
    }

    private func circle(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text.color)
                .frame(width: 30, height: 30).background(Circle().fill(t.surface.color)).overlay(Circle().strokeBorder(t.separatorStrong.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(name == "chevron.left" ? "Previous scene" : "Next scene")   // LAB-1236: icon-only buttons say what they do
    }
}

/// Lays children out left to right, wrapping (the scene's diagram boxes).
struct LearnFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 800
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(w, maxX), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

struct LearnTranscript: View {
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(scenes.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 14) {
                    Button { audio.play(card.slug, scene: i, then: audio.bandFrom(card.slug)) } label: {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).frame(width: 44, alignment: .leading).help("Play from here")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.section) · \(s.kicker)".uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(t.text3.color)
                        Text(s.heading).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color).padding(.top, 2).padding(.bottom, 4)
                        Text(s.narration.isEmpty ? "This scene has no narration in the bundled deck." : s.narration)
                            .font(.system(size: 14)).lineSpacing(4).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(i == idx ? t.selection.color : Color.clear))
                .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        }
        .textSelection(.enabled)
    }
}

struct LearnSkillFile: View {
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let card: DeckCard
    @Environment(\.theme) private var t

    var body: some View {
        let path = audio.deck.skillPath(card.slug)
        VStack(alignment: .leading, spacing: 0) {
            Text(card.skill).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text3.color).padding(.bottom, 10)
            // LAB-1628: the front-matter is YAML in the dark code panel, the body is rendered under it.
            if nav.skill(card.slug, audio.deck) != nil, let text = DeckFolders.text(path) {
                MarkdownWithFrontMatter(text: text, path: path, frontLabel: "SKILL.md · front-matter")
            } else {
                Text("The bundled deck has no SKILL.md for this card.").font(.system(size: 14)).foregroundStyle(t.text2.color)
            }
        }
    }
}

/// The station's right column.
struct LearnCardSide: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    let here: Bool
    /// The native Chapters list: only when the card has no page of its own (LAB-1305; the page has its sections menu).
    var chapters = true
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let band = deck.band(of: card.slug)
        let list = deck.lists[band.id] ?? []
        let at = list.firstIndex(of: card.slug) ?? 0
        let next = Array(list.dropFirst(at + 1).prefix(4))
        let pairs = (nav.skill(card.slug, deck)?.dependencies ?? []).filter { deck.cards[$0] != nil }
        let reads = band.posts.compactMap { s in posts.first { $0.slug == s } }
        let current = scenes.indices.contains(idx) ? scenes[idx].sectionIndex : -1
        VStack(alignment: .leading, spacing: 22) {
            // LAB-1668: a person's card shows their profile first.
            if let person = card.person {
                LearnPersonProfile(card: card, person: person, profile: nav.profile(card.slug, deck), root: deck.root)
            }
            if chapters {
            VStack(alignment: .leading, spacing: 2) {
                LearnRuleHeading(text: "Chapters")
                ForEach(Array(card.sections.enumerated()), id: \.offset) { i, sec in
                    let on = i == current
                    Button {
                        let first = scenes.firstIndex { $0.sectionIndex == i } ?? 0
                        if here { audio.play(card.slug, scene: first, then: audio.bandFrom(card.slug)) } else { nav.scene = first; nav.tab = "listen" }
                    } label: {
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", i + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(on ? t.accentText.color : t.text3.color).frame(width: 22, alignment: .leading)
                            Text(DeckSpec.clean(sec.title)).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(sec.scenes) scene\(sec.scenes == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(t.text3.color)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? t.selection.color : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            }
            VStack(alignment: .leading, spacing: 5) {
                LearnRuleHeading(text: "Say it in a session").padding(.bottom, 3)
                ForEach(card.triggers.prefix(4), id: \.self) { tr in
                    Text("\u{201C}\(tr)\u{201D}").font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text.color)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.surface2.color))
                }
                (Text("Or send ") + Text("/\(card.slug)").font(.system(size: 11, design: .monospaced)) + Text(" to a live session with Use in a session."))
                    .font(.system(size: 11)).foregroundStyle(t.text3.color).padding(.top, 1)
            }
            if !pairs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Pairs with")
                    ForEach(pairs, id: \.self) { k in sideLink(deck.cards[k]?.title ?? k, nil) { nav.openCard(k) } }
                }
            }
            if !reads.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Read about it")
                    ForEach(reads) { p in
                        Button { nav.openPost(p.slug) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text((p.series == "Agentic engineering" ? "Series" : "Field notes") + " · " + LearnPosts.state(p, in: posts, today: LearnPostRow.today).label)
                                    .font(.system(size: 11)).foregroundStyle(t.text3.color)
                                Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Next on the \(band.title) band")
                    ForEach(next, id: \.self) { k in sideLink(deck.cards[k]?.title ?? k, LearnDeck.minutes(deck.cards[k]?.estSeconds ?? 0)) { nav.openCard(k) } }
                }
            }
        }
    }

    private func sideLink(_ title: String, _ trailing: String?, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack {
                Text(title).font(.system(size: 13, weight: trailing == nil ? .semibold : .medium)).foregroundStyle(t.text.color)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(t.text3.color) }
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The card's header actions: Play in One Roof · Use in a session ▾ · Open in browser.
struct LearnCardActions: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    /// Another card than the station's (All cards › By folder's panel, LAB-1253).
    var card: String? = nil
    /// Only "Use in a session ▾" (the panel draws its own Play and links).
    var sessionOnly = false
    @State private var sessionsOpen = false
    @Environment(\.theme) private var t

    var body: some View {
        let slug = card ?? nav.slug
        let here = audio.playingSlug == slug
        HStack(spacing: 6) {
            if !sessionOnly {
            Button { audio.toggle(slug, scene: here ? player.index : nav.scene, then: audio.bandFrom(slug)) } label: {
                HStack(spacing: 6) {
                    Image(systemName: here && player.playing ? "pause.fill" : "play.fill").font(.system(size: 9))
                    Text(here ? (player.playing ? "Pause" : "Resume") : "Play in One Roof")
                }
            }
            .buttonStyle(LearnChipStyle())
            }
            Button { sessionsOpen.toggle() } label: { Text("Use in a session ▾") }
                .buttonStyle(LearnChipStyle())
                .popover(isPresented: $sessionsOpen, arrowEdge: .bottom) { sessions(slug) }
            if !sessionOnly {
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: audio.deck.htmlPath(slug))) } label: {
                HStack(spacing: 6) { Image(systemName: "safari").font(.system(size: 11)); Text("Open in browser") }
            }
            .buttonStyle(LearnChipStyle())
            }
        }
    }

    private func sessions(_ slug: String) -> some View {
        let live = model.items.filter { $0.liveAgent != nil && $0.session.agent.isAgent }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Type /\(slug) as the next message in").font(.system(size: 11)).foregroundStyle(t.text3.color).padding(.horizontal, 8).padding(.vertical, 4)
            if live.isEmpty {
                Text("No live agent session. Start one, then send the card to it.").font(.system(size: 12)).foregroundStyle(t.text2.color)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(live) { i in
                Button {
                    sessionsOpen = false
                    if i.status == .running { nav.flash("\(i.session.name) is working; send /\(slug) when it is idle") }
                    else { model.sendSkill(slug, to: i); nav.flash("Sent /\(slug) to \(i.session.name)") }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(t.statusColor(i.status).color).frame(width: 7, height: 7)
                        Text(i.session.name).font(.system(size: 13)).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                        Text(i.status.rawValue.capitalized).font(.system(size: 11)).foregroundStyle(t.text3.color)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6).frame(minWidth: 280)
    }
}
