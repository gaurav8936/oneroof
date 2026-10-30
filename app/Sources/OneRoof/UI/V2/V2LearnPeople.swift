import AppKit
import SwiftUI
import OneRoofCore

// LAB-1668 · People (Influences) in Learn, from the deck's catalog (0.2.4+): six themes in display order, each person
// with their photo (or initials), name and contribution; and, on a person's card, their profile next to the page (role,
// bio, start here, contributions with links, where they publish, photo credit). The card page renders its own Profile /
// Go deeper block; this is the host's compact view of the same spec.json.

/// A person's photo from the deck (or their initials in a circle).
struct LearnPersonAvatar: View {
    let person: DeckPerson
    let root: String
    var size: CGFloat = 32
    @Environment(\.theme) private var t

    var body: some View {
        Group {
            if let p = person.photo, let img = LearnPersonAvatar.image(root + "/" + p) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(t.selection.color)
                    Text(person.initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(t.accentText.color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(t.separator.color, lineWidth: 1))
        .accessibilityLabel(person.display)
    }

    /// Photos read once per path (a band page shows dozens).
    @MainActor private static var cache: [String: NSImage] = [:]
    @MainActor static func image(_ path: String) -> NSImage? {
        if let i = cache[path] { return i }
        guard let i = NSImage(contentsOfFile: path) else { return nil }
        cache[path] = i
        return i
    }
}

/// One person in a theme: ▶ · photo · name · contribution · length.
struct LearnPersonRow: View {
    let slug: String
    let audio: LearnAudio
    @ObservedObject var player: CoursePlayer
    var queue: [String] = []
    let open: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let c = deck.cards[slug]
        let here = audio.playingSlug == slug
        HStack(spacing: 12) {
            LearnRoundPlay(playing: here && player.playing) { audio.toggle(slug, then: queue.isEmpty ? [slug] : Array(queue.drop { $0 != slug })) }
                .frame(width: 30)
            Button(action: open) {
                HStack(spacing: 12) {
                    if let p = c?.person { LearnPersonAvatar(person: p, root: deck.root, size: 36) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c?.person?.display ?? c?.title ?? slug).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.text.color)
                        Text(c?.person?.tagline ?? c?.subtitle ?? "").font(.system(size: 12.5)).foregroundStyle(t.text2.color).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(LearnDeck.minutes(c?.estSeconds ?? 0)).font(.system(size: 12)).foregroundStyle(t.text3.color).frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(here ? t.selection.color : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }
}

/// A themed track on a band page: the track's heading, then one block per theme (title · question) with its people.
struct LearnThemedTrack: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let track: String
    let themes: [DeckTheme]
    let queue: [String]
    var marked = false
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let people = themes.flatMap(\.cards)
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(LearnDeck.trackNames[track]?.name ?? LearnDeck.label(track)).font(.system(size: 18, weight: .bold)).foregroundColor(t.text.color)
                     + Text(" · \(themes.count) themes").font(.system(size: 13)).foregroundColor(t.text2.color)).lineLimit(1)
                    Spacer()
                    Text("\(people.count) people").font(.system(size: 12)).foregroundStyle(t.text3.color)
                }
                .padding(.bottom, 6)
                Rectangle().fill(marked ? t.accent.color : t.separatorStrong.color).frame(height: marked ? 2 : 1)
            }
            ForEach(themes) { th in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        LearnKicker(text: th.title, size: 11)
                        if !th.question.isEmpty { Text(th.question).font(.system(size: 12.5)).foregroundStyle(t.text2.color).lineLimit(1) }
                        Spacer()
                        Text("\(th.cards.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(t.text3.color)
                    }
                    .padding(.top, 18).padding(.bottom, 4)
                    ForEach(th.cards.filter { deck.cards[$0] != nil }, id: \.self) { k in
                        LearnPersonRow(slug: k, audio: audio, player: player, queue: queue) { nav.openCard(k) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(th.title)
                .id(LearnRadioRoute.anchor(track: track + ":" + th.id))   // band:<id>:<track>:<theme> opens the page there
            }
        }
        .padding(.top, 28)
    }
}

/// On a person's card: the profile next to the page.
struct LearnPersonProfile: View {
    let card: DeckCard
    let person: DeckPerson
    let profile: DeckProfile?
    let root: String
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnRuleHeading(text: "Profile")
            HStack(alignment: .top, spacing: 12) {
                LearnPersonAvatar(person: person, root: root, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.display).font(.system(size: 15, weight: .bold)).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Text(profile?.role ?? person.role).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            Text(person.tagline).font(.system(size: 12.5, weight: .medium)).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            if let p = profile {
                if !p.bio.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(p.bio, id: \.self) { l in Text(l).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.top, 8)
                }
                if let s = p.startHere {
                    LearnRuleHeading(text: "Start here").padding(.top, 16)
                    link(s.title, DeckProfile.meta(s), s.url)
                }
                if !p.sources.isEmpty {
                    LearnRuleHeading(text: "Contributions").padding(.top, 16)
                    ForEach(Array(p.sources.enumerated()), id: \.offset) { _, s in link(s.title, DeckProfile.meta(s), s.url, line: s.line) }
                }
                if !p.publishes.isEmpty {
                    LearnRuleHeading(text: "Where they publish").padding(.top, 16)
                    LearnFlow(spacing: 6) {
                        ForEach(Array(p.publishes.enumerated()), id: \.offset) { _, l in
                            Button { open(l.url) } label: { Text(l.title + " ↗") }.buttonStyle(LearnChipStyle()).help(l.url)
                        }
                    }
                    .padding(.top, 6)
                }
                let credits = p.photos.filter { $0.file != nil && !$0.credit.isEmpty }
                if !credits.isEmpty {
                    Text("Photo: " + credits.map { $0.credit + ($0.licence.isEmpty ? "" : " (\($0.licence))") }.joined(separator: "; "))
                        .font(.system(size: 10.5)).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }
            }
        }
    }

    private func link(_ title: String, _ meta: String, _ url: String, line: String = "") -> some View {
        Button { open(url) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title + " ↗").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.accentText.color).multilineTextAlignment(.leading)
                if !meta.isEmpty { Text(meta).font(.system(size: 10.5)).foregroundStyle(t.text3.color) }
                if !line.isEmpty { Text(line).font(.system(size: 11.5)).foregroundStyle(t.text2.color).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(url)
    }

    private func open(_ url: String) { if let u = URL(string: url), u.scheme == "https" || u.scheme == "http" { NSWorkspace.shared.open(u) } }
}
