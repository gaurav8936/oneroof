import XCTest
@testable import OneRoofCore

/// S07 §1.8 Outline tab: symbols per language, strings and comments ignored.
final class OutlineTests: XCTestCase {
    func item(_ name: String, _ kind: OutlineItem.Kind, _ line: Int, _ depth: Int) -> OutlineItem {
        OutlineItem(name: name, kind: kind, line: line, depth: depth)
    }

    func testPython() {
        let src = """
        MAX_RETRIES = 3
        TIMEOUT: Final = 30
        lower = 1
        if DEBUG == True: pass
        class Client:
            \"\"\"
            def not_a_function(): docstring
            \"\"\"
            def get(self):
                def inner():
                    pass
            async def post(self):
                pass
        # def commented():
        def main():
            pass
        """
        XCTAssertEqual(Outline.items(src, language: .python), [
            item("MAX_RETRIES", .constant, 1, 0),
            item("TIMEOUT", .constant, 2, 0),
            item("Client", .type, 5, 0),
            item("get", .function, 9, 1),
            item("inner", .function, 10, 2),
            item("post", .function, 12, 1),
            item("main", .function, 15, 0),
        ])
    }

    func testSwift() {
        let src = """
        import Foundation

        let defaultName = "x"
        @MainActor
        public final class Store: ObservableObject {
            private(set) var items: [Int] = []
            let local = 1
            init(items: [Int]) { self.items = items }
            @discardableResult public static func load(_ s: String) -> Store {
                let inner = "func fake() {"
                return Store(items: [])
            }
        }
        extension Store.Item: Sendable {}
        enum Mode { case a, b }
        // struct Commented {}
        private func helper<T>(_ t: T) {}
        """
        XCTAssertEqual(Outline.items(src, language: .swift), [
            item("defaultName", .constant, 3, 0),
            item("Store", .type, 5, 0),
            item("init", .function, 8, 1),
            item("load", .function, 9, 1),
            item("Store.Item", .type, 14, 0),
            item("Mode", .type, 15, 0),
            item("helper", .function, 17, 0),
        ])
    }

    func testTypeScript() {
        let src = """
        export const API_URL = "https://x.test";
        const handler = async (req) => { return 1 };
        export default function render() {
          const local = 1;
        }
        export interface Props { id: string }
        type Id = string;
        class Store {}
        /* function hidden() {} */
        let notListed = 2;
        """
        XCTAssertEqual(Outline.items(src, language: .typescript), [
            item("API_URL", .constant, 1, 0),
            item("handler", .function, 2, 0),
            item("render", .function, 3, 0),
            item("Props", .type, 6, 0),
            item("Id", .type, 7, 0),
            item("Store", .type, 8, 0),
        ])
    }

    func testMarkdownShellYAML() {
        let md = """
        # Title
        text
        ## Part one ##
        ```
        # not a heading
        ```
        ### Deep
        """
        XCTAssertEqual(Outline.items(md, language: .markdown), [
            item("Title", .section, 1, 1),
            item("Part one", .section, 3, 2),
            item("Deep", .section, 7, 3),
        ])

        let sh = """
        #!/bin/zsh
        build() {
          echo "deploy() {"
        }
        function deploy {
        }
        """
        XCTAssertEqual(Outline.items(sh, language: .shell), [
            item("build", .function, 2, 0),
            item("deploy", .function, 5, 0),
        ])

        let yaml = "name: ci\non:\n  push: {}\njobs:\n  build: {}\n"
        XCTAssertEqual(Outline.items(yaml, language: .yaml).map(\.name), ["name", "on", "jobs"])
        XCTAssertTrue(Outline.items("{\"a\": 1}", language: .json).isEmpty)
        XCTAssertTrue(Outline.items("def x():", language: .plain).isEmpty)
    }
}
