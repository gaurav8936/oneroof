import XCTest
@testable import OneRoofCore

/// S07 §1.5: per-language lexers. Each fixture checks the runs by their text.
final class LexerTests: XCTestCase {
    /// The coloured runs as (text, kind).
    func runs(_ text: String, _ lang: SourceLanguage) -> [(String, TokenKind)] {
        let ns = text as NSString
        return Lexer.tokens(text, language: lang).map { (ns.substring(with: NSRange(location: $0.location, length: $0.length)), $0.kind) }
    }

    func kind(of piece: String, in r: [(String, TokenKind)]) -> TokenKind? { r.first { $0.0 == piece }?.1 }

    func assertWellFormed(_ text: String, _ lang: SourceLanguage, file: StaticString = #filePath, line: UInt = #line) {
        let toks = Lexer.tokens(text, language: lang)
        var last = 0
        for t in toks {
            XCTAssertGreaterThan(t.length, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(t.location, last, "overlap at \(t)", file: file, line: line)
            last = t.end
        }
        XCTAssertLessThanOrEqual(last, (text as NSString).length, file: file, line: line)
    }

    func testDetect() {
        XCTAssertEqual(SourceLanguage.detect(path: "a/b.py"), .python)
        XCTAssertEqual(SourceLanguage.detect(path: "View.swift"), .swift)
        XCTAssertEqual(SourceLanguage.detect(path: "x.ts"), .typescript)
        XCTAssertEqual(SourceLanguage.detect(path: "x.TSX"), .typescript)
        for e in ["js", "mjs", "cjs", "jsx"] { XCTAssertEqual(SourceLanguage.detect(path: "x.\(e)"), .javascript) }
        for e in ["sh", "zsh", "bash"] { XCTAssertEqual(SourceLanguage.detect(path: "x.\(e)"), .shell) }
        XCTAssertEqual(SourceLanguage.detect(path: "ci.yml"), .yaml)
        XCTAssertEqual(SourceLanguage.detect(path: "ci.yaml"), .yaml)
        XCTAssertEqual(SourceLanguage.detect(path: "package.json"), .json)
        XCTAssertEqual(SourceLanguage.detect(path: "README.md"), .markdown)
        XCTAssertEqual(SourceLanguage.detect(path: "Makefile"), .plain)
        XCTAssertEqual(SourceLanguage.detect(path: "notes.txt"), .plain)
        XCTAssertTrue(Lexer.tokens("anything", language: .plain).isEmpty)
    }

    func testPython() {
        let src = """
        import os  # the os module
        class Greeter(Base):
            def greet(self, name: str) -> Dict:
                s = "it's # not a comment"
                t = 'say "hi"'
                u = "esc \\" still string"
                return f"{name}" + r'raw\\d' + str(42) + hex(0x1F)
        DOC = \"\"\"multi
        line # still string\"\"\"
        """
        let r = runs(src, .python)
        XCTAssertEqual(kind(of: "import", in: r), .keyword)
        XCTAssertEqual(kind(of: "# the os module", in: r), .comment)
        XCTAssertEqual(kind(of: "class", in: r), .keyword)
        XCTAssertEqual(kind(of: "Greeter", in: r), .type)
        XCTAssertEqual(kind(of: "greet", in: r), .function)
        XCTAssertEqual(kind(of: "str", in: r), .type)
        XCTAssertEqual(kind(of: "Dict", in: r), .type)
        XCTAssertEqual(kind(of: "\"it's # not a comment\"", in: r), .string)
        XCTAssertEqual(kind(of: "'say \"hi\"'", in: r), .string)
        XCTAssertEqual(kind(of: "\"esc \\\" still string\"", in: r), .string)
        XCTAssertEqual(kind(of: "f\"{name}\"", in: r), .string)
        XCTAssertEqual(kind(of: "r'raw\\d'", in: r), .string)
        XCTAssertEqual(kind(of: "42", in: r), .number)
        XCTAssertEqual(kind(of: "0x1F", in: r), .number)
        XCTAssertEqual(kind(of: "hex", in: r), .function)
        XCTAssertEqual(kind(of: "\"\"\"multi\nline # still string\"\"\"", in: r), .string)
        XCTAssertFalse(r.contains { $0.1 == .comment && $0.0.contains("still string") })
        XCTAssertFalse(r.contains { $0.1 == .comment && $0.0.contains("not a comment") })
        assertWellFormed(src, .python)
    }

    func testSwift() {
        let src = """
        /* header
           spans lines */
        @MainActor
        public struct Model: Sendable {
            let id: UUID // trailing
            var title = "say \\(user.name("x")) done"
            static let raw = #"a "quoted" \\n"#
            func render(_ x: Int) -> Result<String, Error> { /* a /* nested */ b */ return Foo(x: 1.5e3) }
        }
        let block = \"\"\"
            multi "line" text
            \"\"\"
        #if DEBUG
        """
        let r = runs(src, .swift)
        XCTAssertEqual(kind(of: "/* header\n   spans lines */", in: r), .comment)
        XCTAssertEqual(kind(of: "@MainActor", in: r), .keyword)
        XCTAssertEqual(kind(of: "struct", in: r), .keyword)
        XCTAssertEqual(kind(of: "Model", in: r), .type)
        XCTAssertEqual(kind(of: "Sendable", in: r), .type)
        XCTAssertEqual(kind(of: "UUID", in: r), .type)
        XCTAssertEqual(kind(of: "// trailing", in: r), .comment)
        XCTAssertEqual(kind(of: "\"say \\(user.name(\"x\")) done\"", in: r), .string, "nested quotes inside interpolation")
        XCTAssertEqual(kind(of: "#\"a \"quoted\" \\n\"#", in: r), .string)
        XCTAssertEqual(kind(of: "render", in: r), .function)
        XCTAssertEqual(kind(of: "Result", in: r), .type)
        XCTAssertEqual(kind(of: "Error", in: r), .type)
        XCTAssertEqual(kind(of: "/* a /* nested */ b */", in: r), .comment)
        XCTAssertEqual(kind(of: "Foo", in: r), .type)
        XCTAssertEqual(kind(of: "1.5e3", in: r), .number)
        XCTAssertEqual(kind(of: "\"\"\"\n    multi \"line\" text\n    \"\"\"", in: r), .string)
        XCTAssertEqual(kind(of: "#if", in: r), .keyword)
        XCTAssertEqual(kind(of: "return", in: r), .keyword)
        assertWellFormed(src, .swift)
    }

    func testTypeScriptAndJavaScript() {
        let src = """
        // line comment with 'quote'
        export class Store extends Base implements Api {
          private items: Item[] = [];
          load(id: number): Promise<Item> {
            const url = `/api/${id}?q=${encode(`x`)}`;
            const s = 'it\\'s';
            /* across
               lines */
            return fetch(url).then(r => r.json());
          }
        }
        function* gen() { yield 1 }
        """
        let r = runs(src, .typescript)
        XCTAssertEqual(kind(of: "// line comment with 'quote'", in: r), .comment)
        XCTAssertEqual(kind(of: "class", in: r), .keyword)
        XCTAssertEqual(kind(of: "Store", in: r), .type)
        XCTAssertEqual(kind(of: "Base", in: r), .type)
        XCTAssertEqual(kind(of: "Api", in: r), .type)
        XCTAssertEqual(kind(of: "Item", in: r), .type)
        XCTAssertEqual(kind(of: "number", in: r), .type)
        XCTAssertEqual(kind(of: "Promise", in: r), .type)
        XCTAssertEqual(kind(of: "load", in: r), .function)
        XCTAssertEqual(kind(of: "`/api/${id}?q=${encode(`x`)}`", in: r), .string, "template literal with nested backticks")
        XCTAssertEqual(kind(of: "'it\\'s'", in: r), .string)
        XCTAssertEqual(kind(of: "/* across\n       lines */", in: r), .comment)
        XCTAssertEqual(kind(of: "fetch", in: r), .function)
        XCTAssertEqual(kind(of: "gen", in: r), .function)
        XCTAssertEqual(kind(of: "1", in: r), .number)
        assertWellFormed(src, .typescript)

        let js = "const $el = document.querySelector('#app'); // pick\nnew Map()"
        let j = runs(js, .javascript)
        XCTAssertEqual(kind(of: "const", in: j), .keyword)
        XCTAssertNil(kind(of: "$el", in: j))
        XCTAssertEqual(kind(of: "querySelector", in: j), .function)
        XCTAssertEqual(kind(of: "'#app'", in: j), .string)
        XCTAssertEqual(kind(of: "// pick", in: j), .comment)
        XCTAssertEqual(kind(of: "Map", in: j), .type)
        XCTAssertNil(kind(of: "interface", in: runs("interface", .javascript)), "TS-only keyword")
    }

    func testJSONAndYAML() {
        let json = #"{"name": "one \"roof\"", "count": -12.5, "ok": true, "none": null}"#
        let r = runs(json, .json)
        XCTAssertEqual(kind(of: "\"name\"", in: r), .type)
        XCTAssertEqual(kind(of: #""one \"roof\"""#, in: r), .string)
        XCTAssertEqual(kind(of: "12.5", in: r), .number)
        XCTAssertEqual(kind(of: "true", in: r), .keyword)
        XCTAssertEqual(kind(of: "null", in: r), .keyword)
        assertWellFormed(json, .json)

        let yaml = """
        # config
        name: build-app
        on:
          push: { branches: [main] }
        steps:
          - run: echo "a # b" # trailing
            url: http://x.test/#anchor
            retries: 3
            enabled: true
        """
        let y = runs(yaml, .yaml)
        XCTAssertEqual(kind(of: "# config", in: y), .comment)
        XCTAssertEqual(kind(of: "name", in: y), .keyword)
        XCTAssertEqual(kind(of: "steps", in: y), .keyword)
        XCTAssertEqual(kind(of: "run", in: y), .keyword)
        XCTAssertEqual(kind(of: "\"a # b\"", in: y), .string)
        XCTAssertEqual(kind(of: "# trailing", in: y), .comment)
        XCTAssertFalse(y.contains { $0.1 == .comment && $0.0.contains("anchor") }, "# inside a word is not a comment")
        XCTAssertEqual(kind(of: "3", in: y), .number)
        XCTAssertEqual(kind(of: "true", in: y), .keyword)
        assertWellFormed(yaml, .yaml)
    }

    func testShell() {
        let src = """
        #!/bin/zsh
        set -euo pipefail
        deploy() {
          local count=$# # args
          if [ -n "${TARGET:-}" ]; then echo "to $TARGET # here"; fi
          echo 'single $NOT # var'
        }
        """
        let r = runs(src, .shell)
        XCTAssertEqual(kind(of: "#!/bin/zsh", in: r), .comment)
        XCTAssertEqual(kind(of: "deploy", in: r), .function)
        XCTAssertEqual(kind(of: "local", in: r), .keyword)
        XCTAssertEqual(kind(of: "$#", in: r), .type)
        XCTAssertEqual(kind(of: "# args", in: r), .comment)
        XCTAssertEqual(kind(of: "\"${TARGET:-}\"", in: r), .string)
        XCTAssertEqual(kind(of: "\"to $TARGET # here\"", in: r), .string)
        XCTAssertEqual(kind(of: "'single $NOT # var'", in: r), .string)
        XCTAssertEqual(kind(of: "then", in: r), .keyword)
        XCTAssertEqual(kind(of: "fi", in: r), .keyword)
        assertWellFormed(src, .shell)
    }

    func testMarkdown() {
        let src = """
        # Title
        Some `code span` and a [link](https://x.test) and ![img](a.png).
        #not-a-heading
        <!-- hidden
        note -->
        ```swift
        # not a heading inside a fence
        ```
        ## Section ##
        """
        let r = runs(src, .markdown)
        XCTAssertEqual(kind(of: "# Title", in: r), .keyword)
        XCTAssertEqual(kind(of: "`code span`", in: r), .string)
        XCTAssertEqual(kind(of: "[link](https://x.test)", in: r), .type)
        XCTAssertEqual(kind(of: "![img](a.png)", in: r), .type)
        XCTAssertNil(kind(of: "#not-a-heading", in: r))
        XCTAssertEqual(kind(of: "<!-- hidden\nnote -->", in: r), .comment)
        XCTAssertEqual(kind(of: "```swift\n# not a heading inside a fence\n```\n", in: r), .string)
        XCTAssertEqual(kind(of: "## Section ##", in: r), .keyword)
        assertWellFormed(src, .markdown)
    }

    func testUTF16Offsets() {
        // An emoji is two UTF-16 units; the comment after it must land on NSString offsets.
        let src = "x = \"\u{1F600}\" # done"
        let toks = Lexer.tokens(src, language: .python)
        let comment = toks.first { $0.kind == .comment }!
        XCTAssertEqual((src as NSString).substring(with: NSRange(location: comment.location, length: comment.length)), "# done")
    }

    func testUnterminatedStringStopsAtLineEnd() {
        let r = runs("s = \"open\nx = 1 # c", .python)
        XCTAssertEqual(kind(of: "\"open", in: r), .string)
        XCTAssertEqual(kind(of: "# c", in: r), .comment)
    }

    func testLargeFileIsFast() {
        let chunk = """
        class Thing(Base):
            \"\"\"Doc string.\"\"\"
            def run(self, n: int) -> str:  # comment
                return f"{n}" + 'x' * 3

        """
        let text = String(repeating: chunk, count: 1000)   // 5,000 lines
        let start = Date()
        let toks = Lexer.tokens(text, language: .python)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(toks.count, 10_000)
        // 50 ms is the release budget; debug builds are several times slower, so allow headroom here.
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testSyntaxColoursReadOnSurface() {
        for t in ThemeName.panelChoices {
            let k = t.tokens
            for kind in TokenKind.allCases {
                XCTAssertGreaterThanOrEqual(RGB.contrast(k.syntax(kind), k.surface), 4.5, "\(t) \(kind)")
            }
        }
        XCTAssertEqual(ThemeName.daylight.tokens.syntax(.keyword), RGB(0x9B2393))
        XCTAssertEqual(ThemeName.midnight.tokens.syntax(.comment), RGB(0x7F8C98))
        XCTAssertEqual(ThemeName.daylight.tokens.syntax(.plain), ThemeName.daylight.tokens.text)
    }
}
