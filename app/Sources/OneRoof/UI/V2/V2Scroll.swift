import SwiftUI
import OneRoofCore

/// LAB-1831 · Scroll (⌃⌥⌘4, beside Single · Grid · Wall): one continuous feed across every session, newest at the
/// bottom. Each entry says which session it is from; asks are answered in place, and every session has a reply box for
/// an instruction. What an agent did comes from its finished steps and the FYI feed (never code, diffs or tool output).
struct V2ScrollPage: View {
    /// Captions, feed and chapters redraw this page (LAB-1338: they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController
    /// The session whose reply box is open, and what is typed in it.
    @State private var replyTo: String?
    @State private var reply = ""
    @FocusState private var replyFocused: Bool

    private var entries: [ScrollEntry] {
        let feed = engineState.feed.map { e in
            FeedEvent(id: UUID(uuidString: e.id) ?? UUID(), at: e.at, sessionId: e.sessionId, kind: e.feedKind, text: e.text)
        }
        return ScrollFeed.entries(feed: feed, chapters: engineState.chapters, decisions: model.decisions) { model.item($0) }
    }

    var body: some View {
        let list = entries
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Scroll").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Text("\(Set(list.map(\.sessionId)).count) sessions · \(list.count) moments · \(list.filter(\.needsInput).count) waiting on you · newest at the bottom")
                    .ui(12.5).foregroundStyle(t.text2.color)
                Spacer()
                Button { win.layout = .single; controller.v2Page = nil } label: { Text("‹ Single").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).help("Back to this window (⌃⌥⌘1, Esc)")
            }
            if list.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing yet.").ui(16, .semibold).foregroundStyle(t.text.color)
                    Text("As your sessions finish steps, find things and ask you, their moments line up here.").ui(12.5).foregroundStyle(t.text2.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { n, e in
                                let first = n == 0 || list[n - 1].sessionId != e.sessionId
                                row(e, header: first).id(e.id)
                            }
                            Color.clear.frame(height: 1).id("scroll-bottom")
                        }
                        .padding(.vertical, 6)
                    }
                    .onAppear { proxy.scrollTo("scroll-bottom", anchor: .bottom) }
                    .onChange(of: list.last?.id) { _, _ in withAnimation(Motion.fast) { proxy.scrollTo("scroll-bottom", anchor: .bottom) } }
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scroll: every session's important moments")
    }

    // MARK: Rows

    @ViewBuilder private func row(_ e: ScrollEntry, header: Bool) -> some View {
        let item = model.item(e.sessionId)
        VStack(alignment: .leading, spacing: 4) {
            if header {
                HStack(spacing: 7) {
                    if let item { AgentBadge(item: item, size: 18, status: true) }
                    Text(item?.session.name ?? "Session").ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Text(item.map { $0.account ?? $0.session.agent.displayName } ?? "").ui(11.5).foregroundStyle(t.text3.color)
                    Spacer()
                    if let item {
                        Button { replyTo = replyTo == item.id ? nil : item.id; reply = ""; replyFocused = true } label: {
                            Text(replyTo == item.id ? "Close" : "Reply").ui(11.5, .semibold).foregroundStyle(t.accentText.color)
                        }
                        .buttonStyle(.plain).help("Send this session an instruction")
                        Button { model.reveal(item) } label: { Text("Open ↗").ui(11.5).foregroundStyle(t.text2.color) }
                            .buttonStyle(.plain).help("Open the session's terminal")
                    }
                }
                .padding(.top, 8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(e.at.formatted(date: .omitted, time: .shortened)).ui(11, mono: true).foregroundStyle(t.text3.color)
                    .frame(width: 58, alignment: .leading)
                Text(label(e.kind)).ui(11, .semibold).foregroundStyle(e.needsInput ? t.needsText.color : t.text2.color)
                    .frame(width: 78, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.text).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let a = e.answer {
                        Text("You: " + a + (e.answeredAt.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                            .ui(12).foregroundStyle(t.text2.color)
                    }
                    if e.needsInput, let id = e.decisionId, let d = model.decisions.first(where: { $0.id == id }) { askControls(d) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(e.needsInput ? t.card.color : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(e.needsInput ? t.separatorStrong.color : .clear))
            if header, let item, replyTo == item.id { replyBox(item) }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(_ k: ScrollEntry.Kind) -> String {
        switch k {
        case .step: return "Step"
        case .finding: return "Found"
        case .choice: return "Chose"
        case .subagents: return "Subagents"
        case .done: return "Done"
        case .rotated: return "Handed off"
        case .error: return "Error"
        case .ask: return "Asks you"
        case .question: return "Question"
        case .finished: return "Finished"
        }
    }

    /// An open ask, answered in place: a permission prompt's Allow once / Deny (and its own options), a question or a
    /// finished turn's reply box (the session's Reply opens it).
    @ViewBuilder private func askControls(_ d: Decision) -> some View {
        if d.isQuestion || d.isFinished {
            Text("Answer with Reply above, or in its terminal").ui(11.5).foregroundStyle(t.text2.color)
        } else if let choices = d.choices, !choices.isEmpty {
            HStack(spacing: 6) {
                // A choice that wants your own words is answered in the full card (Needs you), not here.
                ForEach(Array(choices.enumerated()), id: \.offset) { _, c in
                    if c.freeText { RoofButton(c.label + " …", .plain) { controller.v2Open(.needsYou); model.needsPick = d.id.uuidString } }
                    else { RoofButton(c.label, .plain) { model.answer(d, .reply, choice: c) } }
                }
            }
        } else {
            HStack(spacing: 6) {
                RoofButton("Allow once", .primary) { model.answer(d, .allowOnce) }
                RoofButton("Deny", .plain) { model.answer(d, .deny) }
            }
        }
    }

    private func replyBox(_ item: BoardItem) -> some View {
        HStack(spacing: 8) {
            TextField("", text: $reply, prompt: Text("Tell \(item.session.name) what to do next"))
                .textFieldStyle(.plain).ui(13).focused($replyFocused)
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card.color))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(replyFocused ? t.accent.color : t.separator.color))
                .onSubmit { send(item) }
            RoofButton("Send ↩", .primary) { send(item) }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 68)
    }

    private func send(_ item: BoardItem) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // An open question or finished turn of this session takes the reply as its answer (Needs you clears it);
        // otherwise the text goes to the agent's input as an instruction.
        if let d = model.openDecisions.first(where: { $0.sessionId == item.id && ($0.isQuestion || $0.isFinished) }) {
            model.answer(d, .reply, reply: text)
        } else {
            model.sendInstruction(text, to: item)
        }
        reply = ""; replyTo = nil
    }
}
