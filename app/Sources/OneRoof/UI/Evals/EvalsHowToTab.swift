import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2113 · Evals › How to: the walkthrough, scene by scene (OneRoofCore/EvalsHowTo.swift). Each scene opens the tab it
/// talks about; read scenes are remembered. Narration plays through One Roof's player when the packaged deck carries the
/// How to card (narrated-player: the AI-voice disclosure shows); otherwise the scenes show with "Narration coming".
struct EvalsHowToTab: View {
    @ObservedObject var nav: EvalsNav
    let model: AppModel
    @Environment(\.theme) private var t
    @AppStorage(EvalsHowTo.progressKey, store: Prefs.viewState) private var stored = ""
    @State private var narration: EvalsHowTo.NarrationState = .coming
    @State private var checked = false

    var body: some View {
        let done = EvalsHowTo.done(stored)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(done)
                ForEach(Array(EvalsHowTo.scenes.enumerated()), id: \.element.id) { i, s in
                    scene(i, s, read: done.contains(s.id))
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.bottom, 24)
        }
        .onAppear(perform: checkNarration)
    }

    private func header(_ done: Set<String>) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to use Evals").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("Eight short scenes: what Evals is for, a first eval, reading and comparing results, your own sets and judges, and where each thing lives.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    switch narration {
                    case .playable:
                        RoofButton("Play from \(EvalsHowTo.next(done).title)", .primary) { play(EvalsHowTo.next(done).id) }
                            .accessibilityLabel("Play the narrated walkthrough from scene \(EvalsHowTo.next(done).title)")
                    case .coming:
                        Text("Narration coming").ui(TypeScale.small, .semibold).foregroundStyle(t.text3.color)
                            .help("The narrated How to card is not in this build's deck yet; the scenes below are the full walkthrough.")
                    }
                    Text(EvalsHowTo.progressLine(done)).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                    Spacer()
                    if !done.isEmpty { RoofButton("Start over", .plain) { stored = "" } }
                }
                if case .playable = narration {
                    Text(Narration.disclosure).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                        .accessibilityLabel(Narration.detail)
                } else {
                    // The line still shows: the scenes will be narrated by the same AI voice when the card arrives.
                    Text(Narration.disclosure + " Not in this build yet.").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
            }
        }
    }

    private func scene(_ i: Int, _ s: EvalsHowTo.Scene, read: Bool) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.accentText.color)
                    Text(s.title).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    if read { Text("✓ read").ui(TypeScale.caption, .semibold).foregroundStyle(t.statusDone.color) }
                }
                Text(s.body).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let tab = s.tab {
                        RoofButton(s.openLabel + " ›") { mark(s.id); nav.go(tab) }
                            .accessibilityLabel("\(s.openLabel): \(tab.title) tab")
                    }
                    if case .playable = narration {
                        RoofButton("Play this scene", .plain) { mark(s.id); play(s.id) }
                    }
                    if !read { RoofButton("Mark as read", .plain) { mark(s.id) } }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scene \(i + 1) of \(EvalsHowTo.scenes.count): \(s.title)\(read ? ", read" : "")")
    }

    private func mark(_ id: String) {
        var d = EvalsHowTo.done(stored)
        d.insert(id)
        stored = EvalsHowTo.store(d)
    }

    /// Whether the deck carries the How to card with audio: read once, off the main thread (the card's page is a file).
    private func checkNarration() {
        guard !checked else { return }
        checked = true
        guard let deck = model.learnDeck, deck.cards[EvalsHowTo.cardSlug] != nil else { narration = .coming; return }
        let page = deck.htmlPath(EvalsHowTo.cardSlug)
        DispatchQueue.global(qos: .userInitiated).async {
            let n = CourseAudio.tracks(page: page).count
            DispatchQueue.main.async { narration = EvalsHowTo.narration(cardPresent: true, tracks: n) }
        }
    }

    private func play(_ sceneId: String) {
        guard case .playable(let n) = narration, let deck = model.learnDeck else { return }
        LearnAudio(deck: deck, player: model.player).play(EvalsHowTo.cardSlug, scene: EvalsHowTo.track(for: sceneId, tracks: n))
    }
}
