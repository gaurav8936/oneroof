import AppKit
import SwiftUI
import OneRoofCore

// LAB-1253 · Learn › All cards › By folder: the deck's skills folder as this build packages it, as a table
// (NAME · WHAT IT IS · BAND · SIZE) with a panel on the right. A track folder lists its cards with Play all; a skill folder
// shows the card with its actions; a file shows its text (the card page opens the card station). Model: `DeckFolders`.

struct LearnFolderView<Intro: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    /// The panel with nothing selected ("How the map reads", as the other two views).
    @ViewBuilder var intro: () -> Intro
    @Environment(\.theme) private var t

    private var deck: LearnDeck { audio.deck }
    private var selected: String? { nav.libSel.flatMap { $0.hasPrefix("folder:") ? String($0.dropFirst(7)) : nil } }

    var body: some View {
        let rows = DeckFolders.rows(in: deck, expanded: nav.folderOpen)
        let sel = selected.flatMap { s in rows.first { $0.id == s } ?? DeckFolders.entry(s, in: deck) }
        HStack(alignment: .top, spacing: 24) {
            table(rows).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                if let sel { panel(sel) } else { intro() }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
            .frame(width: 420)   // LAB-1628: wider, so the code panel reads (was 380)
        }
    }

    // MARK: The table

    private func table(_ rows: [DeckFolderEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            columns(name: Text("NAME"), what: Text("WHAT IT IS"), band: Text("BAND"), size: Text("SIZE"))
                .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(t.text3.color)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Rectangle().fill(t.separatorStrong.color).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(t.text2.color)
                Text(DeckFolders.rootLabel(deck)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(t.text.color)
                Text("Agentic Engineering \(deck.version) · as packaged in this build").font(.system(size: 11)).foregroundStyle(t.text3.color).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            if rows.isEmpty {
                Text("The skills folder is not in this build.").font(.system(size: 12)).foregroundStyle(t.text2.color).padding(16)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { e in LearnFolderRow(entry: e, nav: nav, audio: audio, open: nav.folderOpen.contains(e.id), selected: selected == e.id) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface.color))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
        .onHover { if !$0 { nav.hover = nil } }
    }

    // MARK: The panel

    @ViewBuilder private func panel(_ e: DeckFolderEntry) -> some View {
        let band = e.track.flatMap { DeckFolders.band(ofTrack: $0) }
        HStack(alignment: .firstTextBaseline) {
            LearnKicker(text: (e.isDir ? e.id : (e.id as NSString).deletingLastPathComponent) + (band.map { " · Band \($0.n) \($0.title)" } ?? ""), size: 10)
                .lineLimit(2)
            Spacer()
            Button { nav.libSel = nil } label: { Text("Close").font(.system(size: 12)).foregroundStyle(t.text3.color) }.buttonStyle(.plain)
        }
        Text(e.isDir ? e.name + "/" : e.name).font(.system(size: 26, weight: .bold)).tracking(-0.5).foregroundStyle(t.text.color)
            .lineLimit(2).padding(.top, 4).padding(.bottom, 2)
        switch e.kind {
        case .track: trackPanel(e)
        case .skill: skillPanel(e)
        default: filePanel(e)
        }
    }

    @ViewBuilder private func trackPanel(_ e: DeckFolderEntry) -> some View {
        let tr = e.track ?? e.name
        let names = LearnDeck.trackNames[tr]
        let ks = DeckFolders.cards(inTrack: tr, deck: deck)
        Text([names?.name ?? e.what, names?.question ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 14)).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
        if let intro = deck.tracks[tr]?.intro, !intro.isEmpty {
            Text(intro).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
        }
        HStack(spacing: 8) {
            LearnPillPlay(label: "Play all \(ks.count)") { if let f = ks.first { audio.play(f, then: ks) } }
            Text(e.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.text3.color).lineLimit(1)
        }
        .padding(.bottom, 8)
        cards(ks)
    }

    @ViewBuilder private func skillPanel(_ e: DeckFolderEntry) -> some View {
        let slug = e.slug ?? e.name
        if let c = deck.cards[slug] {
            Text(c.title + (c.subtitle.isEmpty ? "" : " · " + c.subtitle)).font(.system(size: 14)).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
            Text(c.description).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            HStack(spacing: 8) {
                LearnPillPlay(label: audio.playingSlug == slug && player.playing ? "Playing" : "Play") { audio.toggle(slug, then: audio.bandFrom(slug)) }
                Text("\(LearnDeck.minutes(c.estSeconds)) · \(c.scenes) scenes").font(.system(size: 11)).foregroundStyle(t.text3.color)
            }
            .padding(.bottom, 8)
            LearnFlow(spacing: 6) {
                Button { nav.openCard(slug) } label: { Text("Open the card →") }.buttonStyle(LearnChipStyle())
                LearnCardActions(model: model, nav: nav, player: player, audio: audio, card: slug, sessionOnly: true)
                terminalButton(e.path)
            }
            .padding(.bottom, 16)
        } else {
            Text("A skill folder the catalog does not list; it has no card.").font(.system(size: 12)).foregroundStyle(t.text2.color).padding(.bottom, 10)
            terminalButton(e.path).padding(.bottom, 10)
        }
        LearnRuleHeading(text: "In this folder")
        ForEach(DeckFolders.children(of: e.id, in: deck)) { f in
            Button { pick(f) } label: {
                HStack(spacing: 8) {
                    Image(systemName: f.isDir ? "folder.fill" : "doc").font(.system(size: 11)).foregroundStyle(t.text3.color).frame(width: 14)
                    Text(f.name).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text.color).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(f.size.isEmpty ? f.what : f.size).font(.system(size: 11)).foregroundStyle(t.text3.color).lineLimit(1)
                }
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
        }
    }

    @ViewBuilder private func filePanel(_ e: DeckFolderEntry) -> some View {
        let c = e.slug.flatMap { deck.cards[$0] }
        Text([e.what, c?.title ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 14)).foregroundStyle(t.text.color).padding(.bottom, 10)
        LearnFlow(spacing: 6) {
            if let slug = c?.slug {
                if e.kind == .card || e.kind == .audio || e.kind == .clip {
                    LearnRoundPlay(playing: audio.playingSlug == slug && player.playing, size: 22) { audio.toggle(slug, then: [slug]) }
                }
                Button { nav.openCard(slug, tab: e.kind == .skillFile ? "skill" : e.kind == .spec ? "transcript" : "listen") } label: { Text("Open the card →") }
                    .buttonStyle(LearnChipStyle())
                if e.kind == .skillFile { LearnCardActions(model: model, nav: nav, player: player, audio: audio, card: slug, sessionOnly: true) }
            }
            terminalButton(e.isDir ? e.path : (e.path as NSString).deletingLastPathComponent)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)]) } label: { Text("Show in Finder") }
                .buttonStyle(LearnChipStyle())
        }
        .padding(.bottom, 12)
        if e.readable {
            // LAB-1628: the shared dark code panel, wrapped so no line is cut; a Markdown file shows its front-matter as
            // YAML and its body rendered below (the page itself scrolls, so the panel has no inner scroller to clip it).
            if let text = DeckFolders.text(e.path) {
                let lang = CodeText.language(path: e.path)
                if lang == .markdown {
                    MarkdownWithFrontMatter(text: text, path: e.path, frontLabel: e.name + " · front-matter")
                } else {
                    let p = CodeText.preview(text)
                    CodePanel(code: p.text, language: lang, label: e.name, note: p.cut ? "First 400 lines. Show in Finder for the whole file." : nil)
                }
            } else {
                Text("This file is not text.").font(.system(size: 12)).foregroundStyle(t.text2.color)
            }
        } else if e.isDir {
            Text(e.size.isEmpty ? "" : e.size + " in this folder.").font(.system(size: 12)).foregroundStyle(t.text2.color)
        }
    }

    private func terminalButton(_ dir: String) -> some View {
        Button {
            model.newTerminal(in: dir)
            model.learnMode = false
        } label: { HStack(spacing: 5) { Text(">_").font(.system(size: 11, weight: .semibold, design: .monospaced)); Text("Open in Terminal") } }
            .buttonStyle(LearnChipStyle())
            .help("A new terminal session in \(dir)")
    }

    private func pick(_ f: DeckFolderEntry) { LearnFolderRow.select(f, nav: nav, deck: deck) }

    private func cards(_ ks: [String]) -> some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(ks, id: \.self) { k in
                let c = deck.cards[k]
                HStack(alignment: .top, spacing: 8) {
                    LearnRoundPlay(playing: audio.playingSlug == k && player.playing, size: 22) { audio.toggle(k, then: Array(ks.drop { $0 != k })) }
                    Button { nav.openCard(k) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c?.title ?? k).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                            Text(c?.subtitle ?? "").font(.system(size: 12)).foregroundStyle(t.text2.color).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text(LearnDeck.minutes(c?.estSeconds ?? 0)).font(.system(size: 11)).foregroundStyle(t.text3.color)
                }
                .padding(.horizontal, 4).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(audio.playingSlug == k ? t.selection.color : Color.clear))
                .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        } }
        .frame(maxHeight: 560)
    }
}

/// NAME · WHAT IT IS · BAND · SIZE.
private func columns<A: View, B: View, C: View, D: View>(name: A, what: B, band: C, size: D) -> some View {
    HStack(spacing: 12) {
        name.frame(maxWidth: .infinity, alignment: .leading)
        what.frame(maxWidth: .infinity, alignment: .leading)
        band.frame(width: 104, alignment: .leading)
        size.frame(width: 72, alignment: .trailing)
    }
}

/// One row of the table.
struct LearnFolderRow: View {
    let entry: DeckFolderEntry
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let open: Bool
    let selected: Bool
    @Environment(\.theme) private var t
    @State private var hover = false

    /// A click: folders toggle open and show in the panel; the card page opens the card station; other files show their text.
    static func select(_ e: DeckFolderEntry, nav: LearnNav, deck: LearnDeck) {
        if e.kind == .card, let s = e.slug, deck.cards[s] != nil { nav.openCard(s); return }
        let key = "folder:" + e.id
        if e.isDir {
            if nav.libSel == key, nav.folderOpen.contains(e.id) { nav.folderOpen.remove(e.id) } else { nav.folderOpen.insert(e.id) }
        }
        nav.libSel = key
    }

    var body: some View {
        let e = entry
        let band = e.band.map { audio.deck.band(id: $0) }
        Button { Self.select(e, nav: nav, deck: audio.deck) } label: {
            columns(name:
                HStack(spacing: 6) {
                    Group {
                        if e.isDir {
                            Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(t.text3.color)
                        } else { Color.clear }
                    }
                    .frame(width: 10)
                    Image(systemName: e.isDir ? "folder.fill" : "doc").font(.system(size: 12))
                        .foregroundStyle(e.kind == .track ? t.accent.color : t.text2.color).frame(width: 16)
                    Text(e.name).font(.system(size: 12.5, weight: e.kind == .track ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                }
                .padding(.leading, CGFloat(e.depth) * 22),
                what: Text(e.what).font(.system(size: 12.5)).foregroundStyle(e.kind == .clip || e.kind == .file ? t.text2.color : t.text.color).lineLimit(1),
                band: Group {
                    if let band {
                        Button { nav.openBand(band.id) } label: { Text("\(band.n) \(band.title)").font(.system(size: 11.5)).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).help("Open the \(band.title) band")
                    } else { Color.clear.frame(height: 1) }
                },
                size: Text(e.size).font(.system(size: 11.5)).foregroundStyle(t.text3.color).lineLimit(1))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(selected ? t.selection.color : hover ? t.selection.color.opacity(0.5) : e.depth > 0 ? t.toolbar.color : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if e.kind == .skill, let s = e.slug, audio.deck.cards[s] != nil { nav.openCard(s) } })
        .onHover { h in
            hover = h
            if h { nav.hover = e.slug.flatMap { audio.deck.cards[$0] != nil ? $0 : nil } }
        }
        .accessibilityLabel("\(e.name), \(e.what)" + (e.size.isEmpty ? "" : ", \(e.size)"))
    }
}
