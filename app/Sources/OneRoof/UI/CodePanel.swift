import AppKit
import SwiftUI
import OneRoofCore

// LAB-1628 (owner, 10-29: "anywhere there is code, use a dark code panel so it is obvious it's code") · the one code
// panel Learn uses for Markdown code blocks (cards' Skill file, posts, help pages), SKILL.md front-matter and the By
// folder file preview: dark in light and dark mode alike (the Midnight theme's tokens, no hex here), monospace, syntax
// colour from the editor's lexers (YAML, Markdown, shell, JSON, Swift, TS …), a Copy button, and lines that wrap so no
// text is hidden or clipped.

struct CodePanel: View {
    let code: String
    let language: SourceLanguage
    /// The label top left ("yaml", "SKILL.md · front-matter" …); nil = the language's name.
    var label: String? = nil
    var scale: CGFloat = 1
    /// A line under the code (e.g. "First 400 lines").
    var note: String? = nil
    @State private var copied = false

    /// The panel's colours: Midnight's, whatever the page's theme.
    static let tokens = ThemeName.midnight.tokens

    var body: some View {
        let c = Self.tokens
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label ?? CodeText.label(language)).font(.system(size: 10.5 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.text3.color).lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10.5 * scale))
                        Text(copied ? "Copied" : "Copy").font(.system(size: 11 * scale))
                    }
                    .foregroundStyle(c.text2.color).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(c.surface2.color))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Copy").accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            Rectangle().fill(c.separator.color).frame(height: 1)
            Text(Self.highlighted(code, language, c))
                .font(.system(size: 12.5 * scale, design: .monospaced)).lineSpacing(3)
                .foregroundStyle(c.text.color)
                .fixedSize(horizontal: false, vertical: true)          // wraps, and every line shows (no clipped last line)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, note == nil ? 12 : 6)
            if let note {
                Text(note).font(.system(size: 11 * scale)).foregroundStyle(c.text3.color).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.terminal.background.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c.separatorStrong.color, lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Code, \(label ?? CodeText.label(language))")
    }

    /// Code coloured with the editor's lexer (`Lexer.tokens`) in the panel's colours.
    static func highlighted(_ code: String, _ language: SourceLanguage, _ c: ThemeTokens = tokens) -> AttributedString {
        guard language != .plain else { return AttributedString(code) }
        let ns = code as NSString
        var out = AttributedString()
        var at = 0
        for tok in Lexer.tokens(code, language: language).sorted(by: { $0.location < $1.location })
        where tok.kind != .plain && tok.location >= at && tok.end <= ns.length {
            if tok.location > at { out += AttributedString(ns.substring(with: NSRange(location: at, length: tok.location - at))) }
            var piece = AttributedString(ns.substring(with: NSRange(location: tok.location, length: tok.length)))
            piece.foregroundColor = c.syntax(tok.kind).color
            out += piece
            at = tok.end
        }
        if at < ns.length { out += AttributedString(ns.substring(from: at)) }
        return out
    }
}

/// A Markdown file as Learn shows it (LAB-1628): its front-matter in the code panel as YAML, then the body rendered.
struct MarkdownWithFrontMatter: View {
    let text: String
    let path: String
    var frontLabel = "front-matter"
    @Environment(\.theme) private var t
    @Environment(\.textScale) private var scale

    var body: some View {
        let parts = CodeText.split(text)
        VStack(alignment: .leading, spacing: 12) {
            if let f = parts.front, !f.isEmpty { CodePanel(code: f, language: .yaml, label: frontLabel, scale: scale).padding(.bottom, 6) }
            ForEach(Array(MarkdownDoc.parse(parts.body).enumerated()), id: \.offset) { _, b in
                MarkdownBlockView(block: b, path: path, t: t, scale: scale, depth: 0)
            }
        }
        .textSelection(.enabled)
    }
}
