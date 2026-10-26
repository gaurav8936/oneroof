import AppKit
import SwiftUI
import OneRoofCore

/// Drafts and sent history per session for the composer (kept while One Roof runs).
@MainActor final class V2ComposerStore {
    static let shared = V2ComposerStore()
    var drafts: [String: String] = [:]
    var history: [String: [String]] = [:]
}

/// The composer under an agent's terminal (handover A1, NEW-1): a text box that writes into the agent's prompt, as if
/// typed in the terminal (roofd input, then Enter). ↩ sends · ⇧↩ new line · ↑ in an empty box brings back the last
/// message · ⌃↩ runs it as a shell command (Claude's "!" mode) · ⌘. interrupts · / skill and @ file are typed as text,
/// for the agent to complete. While the agent waits on a decision it does not send (the Enter would answer the prompt):
/// answer the card above first. The terminal itself is unchanged and still takes typing.
struct V2Composer: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem
    var raw: Bool
    var onRaw: () -> Void
    @State private var note: String?
    @State private var focused = false

    private var who: String { item.account ?? item.session.agent.displayName }
    private var waiting: Bool { item.status == .needsYou }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("❯").ui(12).foregroundStyle(t.accentText.color)
            ComposerField(placeholder: waiting ? "\(who) is waiting on the decision above" : "Message \(who)…",
                          sessionId: item.id, textColor: t.text.nsColor, placeholderColor: t.text3.nsColor,
                          onSend: { text, shell in send(text, asShell: shell) },
                          onInterrupt: { model.interrupt(item) },
                          onFocus: { focused = $0 })
                .frame(height: 22)
                .help("↩ send · ⇧↩ new line · ↑ last message · ⌃↩ run as shell · ⌘. interrupt")
            if let note { Text(note).ui(11).foregroundStyle(t.text3.color).lineLimit(1) }
            else { Text("/ skill · @ file · ⌃↩ run as shell · ⌘. interrupt").ui(11).foregroundStyle(t.text3.color).lineLimit(1) }
            Button(action: onRaw) {
                Text(raw ? "Chapters ⌘R" : "Raw stream ⌘R").ui(11, mono: true).foregroundStyle(t.text2.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(t.surface2.color))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(focused ? t.accent.color : t.separatorStrong.color).padding(.horizontal, 12).padding(.vertical, 4))
        .frame(height: 46)
        .background(t.terminal.background.color)
    }

    /// Writes the text into the agent's prompt and presses Enter, exactly as typing it would. Returns false = kept.
    private func send(_ raw: String, asShell: Bool) -> Bool {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        if waiting { note = "Answer the decision first; your text is kept"; return false }
        guard let agent = item.liveAgent else { note = "The agent isn't running"; return false }
        if asShell && item.session.agent != .claude { note = "Run as shell works with Claude (its ! mode)"; return false }
        note = nil
        let message = asShell ? "!" + body : body
        V2ComposerStore.shared.history[item.id, default: []].append(body)
        let r = model.runtime
        DispatchQueue.global().async { try? r.submit(agent, text: message) }
        return true
    }
}

/// The composer's text box: an NSTextView, so Return arrives as insertNewline: only after an input method has
/// committed its text (Japanese, Chinese…), ⇧↩ inserts a line, ↑ in an empty box recalls history, ⌘. interrupts.
struct ComposerField: NSViewRepresentable {
    let placeholder: String
    let sessionId: String
    let textColor: NSColor
    let placeholderColor: NSColor
    var onSend: (String, Bool) -> Bool
    var onInterrupt: () -> Void
    var onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let tv = scroll.documentView as! NSTextView
        let box = ComposerTextView(frame: tv.frame, textContainer: tv.textContainer)
        box.autoresizingMask = tv.autoresizingMask
        box.minSize = tv.minSize; box.maxSize = tv.maxSize
        box.isVerticallyResizable = true; box.isHorizontallyResizable = false
        box.textContainer?.widthTracksTextView = true
        box.drawsBackground = false
        box.isRichText = false
        box.allowsUndo = true
        box.isAutomaticQuoteSubstitutionEnabled = false; box.isAutomaticDashSubstitutionEnabled = false
        box.font = NSFont.systemFont(ofSize: 12.5)
        box.textContainerInset = NSSize(width: 0, height: 3)
        box.delegate = context.coordinator
        box.coordinator = context.coordinator
        box.string = V2ComposerStore.shared.drafts[sessionId] ?? ""
        scroll.documentView = box
        context.coordinator.box = box
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let box = context.coordinator.box else { return }
        box.textColor = textColor
        box.insertionPointColor = textColor
        box.placeholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: NSFont.systemFont(ofSize: 12.5)])
        if context.coordinator.sessionId != sessionId {   // another session's composer: its own draft
            context.coordinator.sessionId = sessionId
            box.string = V2ComposerStore.shared.drafts[sessionId] ?? ""
            context.coordinator.back = 0
        }
        box.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerField
        weak var box: ComposerTextView?
        var sessionId: String
        var back = 0
        init(_ p: ComposerField) { parent = p; sessionId = p.sessionId }

        func textDidChange(_ n: Notification) { V2ComposerStore.shared.drafts[sessionId] = box?.string }
        func textDidBeginEditing(_ n: Notification) { parent.onFocus(true) }
        func textDidEndEditing(_ n: Notification) { parent.onFocus(false) }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if mods.contains(.shift) { tv.insertText("\n", replacementRange: tv.selectedRange()); return true }
                if parent.onSend(tv.string, mods.contains(.control)) {
                    tv.string = ""; back = 0; V2ComposerStore.shared.drafts[sessionId] = nil
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                tv.insertText("\n", replacementRange: tv.selectedRange()); return true
            case #selector(NSResponder.moveUp(_:)):
                guard tv.string.isEmpty || back > 0, let h = V2ComposerStore.shared.history[sessionId], !h.isEmpty else { return false }
                back = min(back + 1, h.count); tv.string = h[h.count - back]; return true
            case #selector(NSResponder.moveDown(_:)):
                guard back > 0, let h = V2ComposerStore.shared.history[sessionId] else { return false }
                back -= 1; tv.string = back == 0 ? "" : h[h.count - back]; return true
            default: return false
            }
        }
    }
}

final class ComposerTextView: NSTextView {
    weak var coordinator: ComposerField.Coordinator?
    var placeholder: NSAttributedString?

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if window?.firstResponder === self, e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           e.charactersIgnoringModifiers == "." { coordinator?.parent.onInterrupt(); return true }
        return super.performKeyEquivalent(with: e)
    }

    override func draw(_ r: NSRect) {
        super.draw(r)
        if string.isEmpty, let placeholder { placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)) }
    }
}
