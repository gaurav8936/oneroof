import XCTest
@testable import OneRoofCore

/// LAB-479 / LAB-480: Markdown and HTML open formatted in the centre, with Source one click away.
final class DocumentViewerTests: XCTestCase {
    // MARK: Routing

    func test_LAB480_kindByExtension() {
        XCTAssertEqual(DocumentRoute.kind(path: "/r/README.md"), .markdown)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/notes.MARKDOWN"), .markdown)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/site/index.html"), .html)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/site/old.HTM"), .html)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/a.png"), .image)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/main.swift"), .text)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/Dockerfile"), .text)
        XCTAssertEqual(DocumentRoute.kind(path: "/r/archive.zip"), .other)
    }

    func test_LAB479_markdownAndHtmlPreviewByDefaultSourceInEditor() {
        for k in [ViewerFileKind.markdown, .html] {
            XCTAssertTrue(DocumentRoute.hasPreview(k))
            XCTAssertFalse(DocumentRoute.opensInEditor(k, mode: .preview), "\(k) renders formatted by default")
            XCTAssertTrue(DocumentRoute.opensInEditor(k, mode: .source), "\(k) Source mode is the editor")
        }
        XCTAssertTrue(DocumentRoute.opensInEditor(.text, mode: .preview))
        XCTAssertFalse(DocumentRoute.opensInEditor(.image, mode: .source))
        XCTAssertFalse(DocumentRoute.hasPreview(.text))
    }

    func test_LAB480_htmlReadsItsRepoSoRelativeAssetsLoad() {
        XCTAssertEqual(DocumentRoute.webReadRoot(page: "/p/repo/site/docs/a.html", repoRoot: "/p/repo"), "/p/repo")
        XCTAssertEqual(DocumentRoute.webReadRoot(page: "/tmp/x/a.html", repoRoot: nil), "/tmp/x")
        XCTAssertEqual(DocumentRoute.webReadRoot(page: "/p/repo2/a.html", repoRoot: "/p/repo"), "/p/repo2")
        XCTAssertEqual(DocumentRoute.enclosingRepo(of: "/p/repo/site/docs/a.html", exists: { $0 == "/p/repo/.git" }), "/p/repo")
        XCTAssertNil(DocumentRoute.enclosingRepo(of: "/tmp/x/a.html", exists: { _ in false }))
    }

    func test_LAB480_webLinksOpenInTheBrowserLocalPagesStay() {
        XCTAssertEqual(WebLinkPolicy.decide("file:///p/site/b.html", clicked: true), .allow)
        XCTAssertEqual(WebLinkPolicy.decide("https://example.com", clicked: true), .openExternally)
        XCTAssertEqual(WebLinkPolicy.decide("https://cdn.example.com/embed", clicked: false), .allow)
        XCTAssertEqual(WebLinkPolicy.decide("mailto:a@b.c", clicked: true), .openExternally)
        XCTAssertEqual(WebLinkPolicy.decide("about:blank", clicked: false), .allow)
        XCTAssertEqual(WebLinkPolicy.decide("javascript:void(0)", clicked: true), .ignore)
    }

    // MARK: Markdown blocks

    func test_LAB479_headingsParagraphsAndFrontmatter() {
        let blocks = MarkdownDoc.parse("---\ntitle: x\n---\n# One Roof\nIntro line\nstill intro.\n\nSetext\n---\n## Two ##\n#not-a-heading")
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "One Roof", anchor: "one-roof"),
            .paragraph("Intro line still intro."),
            .heading(level: 2, text: "Setext", anchor: "setext"),
            .heading(level: 2, text: "Two", anchor: "two"),
            .paragraph("#not-a-heading"),
        ])
    }

    func test_LAB479_nestedAndTaskLists() {
        let md = """
        - one
        - two
          - two a
          - [x] two b
        - [ ] three

        1. first
        2. second
        """
        let blocks = MarkdownDoc.parse(md)
        XCTAssertEqual(blocks.count, 2)
        guard case .list(false, _, let items) = blocks[0] else { return XCTFail("bullet list") }
        XCTAssertEqual(items.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(items[2].checked, false)
        guard case .list(false, _, let nested)? = items[1].children.first else { return XCTFail("nested list") }
        XCTAssertEqual(nested.map(\.text), ["two a", "two b"])
        XCTAssertEqual(nested[1].checked, true)
        guard case .list(true, 1, let ordered) = blocks[1] else { return XCTFail("ordered list") }
        XCTAssertEqual(ordered.map(\.text), ["first", "second"])
    }

    func test_LAB479_codeFencesKeepTextAndLanguage() {
        let blocks = MarkdownDoc.parse("```swift title=x\nlet a = 1\n\n# not a heading\n```\nafter\n\n    indented()\n")
        XCTAssertEqual(blocks, [
            .code(language: "swift", text: "let a = 1\n\n# not a heading"),
            .paragraph("after"),
            .code(language: "", text: "indented()"),
        ])
    }

    func test_LAB479_tablesWithAlignment() {
        let blocks = MarkdownDoc.parse("| Key | Count | Note |\n|:--|--:|:-:|\n| a | 1 | `x|y` |\n| b \\| c | 2 |")
        XCTAssertEqual(blocks, [.table(header: ["Key", "Count", "Note"], alignments: [.leading, .trailing, .center],
                                       rows: [["a", "1", "`x|y`"], ["b | c", "2", ""]])])
    }

    func test_LAB479_quotesRulesImagesAndHtml() {
        let md = "> quoted\n> **still**\n\n***\n\n![Diagram](img/flow.png \"Flow\")\n\n<!-- hidden\nnote -->\n<p align=\"center\"><img src=\"logo.svg\" alt=\"Logo\"></p>"
        XCTAssertEqual(MarkdownDoc.parse(md), [
            .quote([.paragraph("quoted **still**")]),
            .rule,
            .image(alt: "Diagram", source: "img/flow.png"),
            .image(alt: "Logo", source: "logo.svg"),
        ])
    }

    func test_LAB479_htmlHeadingsAndLinksInMarkdown() {
        XCTAssertEqual(MarkdownDoc.parse("<h1 align=\"center\">One Roof</h1>\n\n<p><a href=\"https://x.y\">Site</a><br>Docs</p>"), [
            .heading(level: 1, text: "One Roof", anchor: "one-roof"),
            .paragraph("[Site](https://x.y)\nDocs"),
        ])
        XCTAssertEqual(MarkdownDoc.parse("<a href=\"https://x.y\"><img src=\"b.svg\" alt=\"Badge\"></a>"), [.image(alt: "Badge", source: "b.svg")])
    }

    func test_LAB479_hardLineBreaks() {
        XCTAssertEqual(MarkdownDoc.parse("a  \nb\\\nc\nd"), [.paragraph("a\nb\nc d")])
    }

    // MARK: Links and images relative to the file

    func test_LAB479_linksResolveAgainstTheFile() {
        let f = "/p/repo/docs/guide.md"
        XCTAssertEqual(MarkdownDoc.resolve("../README.md#setup", from: f), .file(path: "/p/repo/README.md", anchor: "setup"))
        XCTAssertEqual(MarkdownDoc.resolve("img/a%20b.png", from: f), .file(path: "/p/repo/docs/img/a b.png", anchor: nil))
        XCTAssertEqual(MarkdownDoc.resolve("/abs/x.md", from: f), .file(path: "/abs/x.md", anchor: nil))
        XCTAssertEqual(MarkdownDoc.resolve("#install", from: f), .anchor("install"))
        XCTAssertEqual(MarkdownDoc.resolve("https://example.com/a", from: f), .web("https://example.com/a"))
        XCTAssertEqual(MarkdownDoc.resolve("mailto:a@b.c", from: f), .web("mailto:a@b.c"))
        XCTAssertEqual(MarkdownDoc.resolve("file:///tmp/x.md", from: f), .file(path: "/tmp/x.md", anchor: nil))
        XCTAssertNil(MarkdownDoc.resolve("  ", from: f))
    }

    func test_LAB479_slugsMatchGitHubAnchors() {
        XCTAssertEqual(MarkdownDoc.slug("Install & Run (macOS 14+)"), "install--run-macos-14")
        XCTAssertEqual(MarkdownDoc.fenceLanguage("Python {linenos}"), "python")
        XCTAssertEqual(MarkdownDoc.sourceLanguage(fence: "python"), .python)
        XCTAssertEqual(MarkdownDoc.sourceLanguage(fence: "bash"), .shell)
        XCTAssertEqual(MarkdownDoc.sourceLanguage(fence: "rust"), .plain)
    }
}
