import AppKit
import SwiftUI
import WebKit
import OneRoofCore

// LAB-479 / LAB-480: the formatted pages the centre shows for a document — Markdown drawn natively from
// MarkdownDoc's blocks, HTML in WebKit like a browser. Used by the centre viewer and by Learn.

/// A local HTML page in WebKit, allowed to read `root` so relative CSS, scripts, images and audio load in place.
/// JavaScript runs; a clicked web link opens in the default browser (WebLinkPolicy), local pages stay in the viewer.
struct WebPage: NSViewRepresentable {
    let path: String
    let root: String
    /// Bumped to reload the page (the viewer's ↻).
    var reload = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.allowsBackForwardNavigationGestures = true
        w.setAccessibilityLabel((path as NSString).lastPathComponent)
        load(w, context)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        if context.coordinator.loadedPath != path || context.coordinator.reload != reload { load(w, context) }
    }

    private func load(_ w: WKWebView, _ context: Context) {
        context.coordinator.loadedPath = path
        context.coordinator.reload = reload
        w.loadFileURL(URL(fileURLWithPath: path), allowingReadAccessTo: URL(fileURLWithPath: root, isDirectory: true))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedPath = ""
        var reload = 0

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let clicked = action.navigationType == .linkActivated || action.navigationType == .formSubmitted
            switch WebLinkPolicy.decide(url.absoluteString, clicked: clicked) {
            case .allow: decisionHandler(.allow)
            case .openExternally: NSWorkspace.shared.open(url); decisionHandler(.cancel)
            case .ignore: decisionHandler(.cancel)
            }
        }

        /// target="_blank" and window.open: web pages go to the browser, local pages load here.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if url.isFileURL { webView.load(action.request) } else if WebLinkPolicy.decide(url.absoluteString, clicked: true) == .openExternally {
                    NSWorkspace.shared.open(url)
                }
            }
            return nil
        }
    }
}

/// A Markdown page drawn natively: headings, paragraphs, nested and task lists, coloured code blocks, quotes, tables,
/// rules and images (relative to the file). Links: other local files open in the viewer, `#heading` scrolls, web
/// links open in the browser.
struct MarkdownPage: View {
    let path: String
    /// Text to show instead of the file (the editor's unsaved buffer).
    var text: String? = nil
    /// Colours; nil = the environment theme.
    var tokens: ThemeTokens? = nil
    /// Open a local file the page links to; nil = its default app.
    var onOpenFile: ((String) -> Void)? = nil

    @Environment(\.theme) private var envTheme
    @Environment(\.textScale) private var scale

    /// The page without its `---` frontmatter block.
    static func body(_ text: String) -> String { MarkdownDoc.stripFrontmatter(text) }

    var body: some View {
        let source = text ?? (try? String(contentsOfFile: path, encoding: .utf8)) ?? "Not found: \(path)"
        let blocks = MarkdownCache.blocks(source)
        let t = tokens ?? envTheme
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        MarkdownBlockView(block: b, path: path, t: t, scale: scale, depth: 0)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 40).padding(.vertical, 30)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .environment(\.openURL, OpenURLAction { url in open(url, proxy) })
        }
        .foregroundStyle(t.text.color)
        .background(t.background.color)
    }

    private func open(_ url: URL, _ proxy: ScrollViewProxy) -> OpenURLAction.Result {
        guard let target = MarkdownDoc.resolve(url.absoluteString, from: path) else { return .discarded }
        switch target {
        case .anchor(let a):
            withAnimation(Motion.base) { proxy.scrollTo(a, anchor: .top) }
            return .handled
        case .file(let p, let a):
            if p == path, let a { withAnimation(Motion.base) { proxy.scrollTo(a, anchor: .top) }; return .handled }
            guard FileManager.default.fileExists(atPath: p) else { return .discarded }
            if let onOpenFile { onOpenFile(p); return .handled }
            return .systemAction(URL(fileURLWithPath: p))
        case .web(let s):
            guard let u = URL(string: s) else { return .discarded }
            return .systemAction(u)
        }
    }
}

/// Parsing is cheap but the viewer redraws often: keep the last few results.
private enum MarkdownCache {
    nonisolated(unsafe) static var last: [(String, [MarkdownBlock])] = []
    static func blocks(_ source: String) -> [MarkdownBlock] {
        if let hit = last.first(where: { $0.0 == source }) { return hit.1 }
        let b = MarkdownDoc.parse(source)
        last.insert((source, b), at: 0)
        if last.count > 4 { last.removeLast() }
        return b
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let path: String
    let t: ThemeTokens
    let scale: CGFloat
    let depth: Int

    var body: some View {
        switch block {
        case .heading(let level, let text, let anchor): heading(level, text).id(anchor)
        case .paragraph(let s):
            Text(inline(s, size: 14)).font(.system(size: 14 * scale)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items): list(ordered, start, items)
        case .code(let lang, let code): codeBlock(lang, code)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(t.separatorStrong.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 10) { nested(inner) }.foregroundStyle(t.text2.color)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let aligns, let rows): table(header, aligns, rows)
        case .image(let alt, let src): MarkdownImage(alt: alt, source: src, path: path, t: t)
        case .rule: Rectangle().fill(t.separator.color).frame(height: 1).padding(.vertical, 6)
        }
    }

    private func nested(_ blocks: [MarkdownBlock]) -> some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
            AnyView(MarkdownBlockView(block: b, path: path, t: t, scale: scale, depth: depth + 1))
        }
    }

    @ViewBuilder private func heading(_ level: Int, _ text: String) -> some View {
        let size: CGFloat = [26, 20.5, 17, 15, 14, 13][min(max(level, 1), 6) - 1]
        VStack(alignment: .leading, spacing: 6) {
            Text(inline(text, size: size)).font(.system(size: size * scale, weight: level <= 2 ? .bold : .semibold))
                .foregroundStyle(level == 6 ? t.text2.color : t.text.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if level <= 2 { Rectangle().fill(t.separator.color).frame(height: 1) }
        }
        .padding(.top, level <= 2 ? 10 : 4)
    }

    private func list(_ ordered: Bool, _ start: Int, _ items: [MarkdownListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(ordered ? "\(start + n)." : nil, checked: item.checked)
                    VStack(alignment: .leading, spacing: 6) {
                        if !item.text.isEmpty {
                            Text(inline(item.text, size: 14)).font(.system(size: 14 * scale)).lineSpacing(3)
                                .strikethrough(item.checked == true, color: t.text3.color)
                                .foregroundStyle(item.checked == true ? t.text2.color : t.text.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        nested(item.children)
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder private func marker(_ number: String?, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13 * scale)).foregroundStyle(checked ? t.accent.color : t.text3.color)
                .accessibilityLabel(checked ? "done" : "not done")
        } else if let number {
            Text(number).font(.system(size: 14 * scale).monospacedDigit()).foregroundStyle(t.text2.color)
                .frame(minWidth: 20 * scale, alignment: .trailing)
        } else {
            Group {
                if depth % 3 == 1 { Circle().strokeBorder(t.text2.color, lineWidth: 1.2) }
                else if depth % 3 == 2 { RoundedRectangle(cornerRadius: 1).fill(t.text2.color) }
                else { Circle().fill(t.text2.color) }
            }
            .frame(width: 5.5 * scale, height: 5.5 * scale)
            .frame(width: 12 * scale)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
        }
    }

    private func codeBlock(_ lang: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(.system(size: 10.5 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(t.text3.color)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 11 * scale)).foregroundStyle(t.text3.color) }
                    .buttonStyle(.borderless).help("Copy").accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12).padding(.top, 7)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlighted(code, lang)).font(.system(size: 12.5 * scale, design: .monospaced)).lineSpacing(2)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 11)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface2.color))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separator.color))
    }

    private func table(_ header: [String], _ aligns: [MarkdownAlignment], _ rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { i, h in
                        cell(h, align: aligns[safe: i] ?? .leading, bold: true).gridColumnAlignment(gridAlign(aligns[safe: i]))
                    }
                }
                .background(t.surface2.color)
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { i, c in cell(c, align: aligns[safe: i] ?? .leading, bold: false) }
                    }
                    .background(r % 2 == 1 ? t.surface2.color.opacity(0.5) : Color.clear)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.separator.color))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(1)
        }
    }

    private func cell(_ s: String, align: MarkdownAlignment, bold: Bool) -> some View {
        Text(inline(s, size: 13)).font(.system(size: 13 * scale, weight: bold ? .semibold : .regular))
            .multilineTextAlignment(align == .center ? .center : align == .trailing ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380, alignment: align == .center ? .center : align == .trailing ? .trailing : .leading)
            .padding(.horizontal, 11).padding(.vertical, 7)
    }

    private func gridAlign(_ a: MarkdownAlignment?) -> HorizontalAlignment {
        switch a { case .center: return .center; case .trailing: return .trailing; default: return .leading }
    }

    /// Inline Markdown (bold, italics, code, links, strikethrough) with links and code in theme colours.
    private func inline(_ s: String, size: CGFloat) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                                    failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(s)
        for run in a.runs {
            if run.link != nil {
                a[run.range].foregroundColor = t.accentText.color
                a[run.range].underlineStyle = .single
            }
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                a[run.range].font = .system(size: size * 0.9 * scale, design: .monospaced)
                a[run.range].backgroundColor = t.surface2.color
            }
        }
        return a
    }

    /// Code coloured with the editor's lexer when the fence names a language it knows.
    private func highlighted(_ code: String, _ lang: String) -> AttributedString {
        let language = MarkdownDoc.sourceLanguage(fence: lang)
        guard language != .plain else { return AttributedString(code) }
        let ns = code as NSString
        var out = AttributedString()
        var at = 0
        for tok in Lexer.tokens(code, language: language).sorted(by: { $0.location < $1.location })
        where tok.kind != .plain && tok.location >= at && tok.end <= ns.length {
            if tok.location > at { out += AttributedString(ns.substring(with: NSRange(location: at, length: tok.location - at))) }
            var piece = AttributedString(ns.substring(with: NSRange(location: tok.location, length: tok.length)))
            piece.foregroundColor = t.syntax(tok.kind).color
            out += piece
            at = tok.end
        }
        if at < ns.length { out += AttributedString(ns.substring(from: at)) }
        return out
    }
}

/// An image in a Markdown page: a local file relative to the page, or a web image; the alt text when it cannot load.
private struct MarkdownImage: View {
    let alt: String
    let source: String
    let path: String
    let t: ThemeTokens

    var body: some View {
        switch MarkdownDoc.resolve(source, from: path) {
        case .file(let p, _)?:
            if let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: min(img.size.width, 820), alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel(alt.isEmpty ? (p as NSString).lastPathComponent : alt)
            } else { missing }
        case .web(let s)?:
            AsyncImage(url: URL(string: s)) { phase in
                if let image = phase.image { image.resizable().scaledToFit().frame(maxWidth: 820, alignment: .leading) }
                else if phase.error != nil { missing } else { ProgressView().controlSize(.small) }
            }
            .accessibilityLabel(alt)
        default: missing
        }
    }

    private var missing: some View {
        Label(alt.isEmpty ? source : alt, systemImage: "photo").font(.system(size: 12.5)).foregroundStyle(t.text3.color)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separator.color))
            .help(source)
    }
}
