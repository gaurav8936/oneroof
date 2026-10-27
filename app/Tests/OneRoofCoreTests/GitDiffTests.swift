import XCTest
@testable import OneRoofCore

final class GitDiffTests: XCTestCase {
    let sample = """
    diff --git a/src/a.swift b/src/a.swift
    index 1111111..2222222 100644
    --- a/src/a.swift
    +++ b/src/a.swift
    @@ -1,4 +1,5 @@ struct A {
     let x = 1
    -let y = 2
    +let y = 3
    +let z = 4
     let w = 5
     let v = 6
    @@ -20,2 +21,2 @@
    -old
    +new
    \\ No newline at end of file
    diff --git a/docs/new.md b/docs/new.md
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/docs/new.md
    @@ -0,0 +1,2 @@
    +# Title
    +body
    diff --git a/old.txt b/renamed.txt
    similarity index 100%
    rename from old.txt
    rename to renamed.txt

    """

    func testParseFilesHunksAndLineNumbers() {
        let files = GitDiff.parse(sample)
        XCTAssertEqual(files.map(\.path), ["src/a.swift", "docs/new.md", "renamed.txt"])
        XCTAssertEqual(files.map(\.change), [.modified, .added, .renamed])
        XCTAssertEqual(files[2].oldPath, "old.txt")
        let a = files[0]
        XCTAssertEqual(a.hunks.count, 2)
        XCTAssertEqual(a.added, 3); XCTAssertEqual(a.removed, 2)
        let h = a.hunks[0]
        XCTAssertEqual(h.lines.map(\.kind), [.context, .removed, .added, .added, .context, .context])
        XCTAssertEqual(h.lines[1].oldNo, 2); XCTAssertEqual(h.lines[2].newNo, 2); XCTAssertEqual(h.lines[4].newNo, 4)
        XCTAssertEqual(h.firstNewLine, 2)
        XCTAssertEqual(a.hunks[1].firstNewLine, 21)
        XCTAssertEqual(a.hunks[1].lines.last?.kind, .note)
        XCTAssertTrue(h.patch.hasPrefix("diff --git a/src/a.swift b/src/a.swift\n--- a/src/a.swift\n"))
        XCTAssertTrue(h.patch.contains("+++ b/src/a.swift\n@@ -1,4 +1,5 @@"))
        XCTAssertFalse(h.patch.contains("@@ -20,2"), "a hunk patch holds only its own hunk")
        XCTAssertEqual(GitDiff.reviewMessage("why 3?", hunk: h), "Review comment on src/a.swift:2 (@@ -1,4 +1,5 @@ struct A {): why 3?")
    }

    func testLoadAndRevertOneHunkInARealRepo() throws {
        let repo = NSTemporaryDirectory() + "oneroof-gitdiff-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repo) }
        func git(_ a: String...) { _ = Foundations.run(GitDiff.git, ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t"] + a) }
        let original = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try original.write(toFile: repo + "/f.txt", atomically: true, encoding: .utf8)
        git("init", "-q"); git("add", "."); git("commit", "-qm", "init")
        var lines = original.components(separatedBy: "\n")
        lines[1] = "CHANGED 2"; lines[25] = "CHANGED 26"
        try lines.joined(separator: "\n").write(toFile: repo + "/f.txt", atomically: true, encoding: .utf8)
        try "x\n".write(toFile: repo + "/new.txt", atomically: true, encoding: .utf8)

        XCTAssertNotNil(GitDiff.repoRoot(for: repo))
        let snap = GitDiff.load(repo: repo)
        XCTAssertNil(snap.error)
        XCTAssertEqual(snap.files.map(\.path), ["f.txt", "new.txt"])
        XCTAssertEqual(snap.files[1].change, .untracked)
        XCTAssertEqual(snap.files[0].hunks.count, 2)

        let st = try XCTUnwrap(GitDiff.stat(repo: repo))
        XCTAssertEqual([st.added, st.removed, st.files], [2, 2, 2])
        XCTAssertFalse(st.branch.isEmpty)
        XCTAssertNil(GitDiff.stat(repo: NSTemporaryDirectory()))
        XCTAssertEqual(GitDiff.parseNumstat("3\t1\ta.swift\n-\t-\timg.png\n"), RepoStat(branch: "", added: 3, removed: 1, files: 2))

        XCTAssertNil(GitDiff.revert(snap.files[0].hunks[0], repo: repo))
        let after = try String(contentsOfFile: repo + "/f.txt", encoding: .utf8)
        XCTAssertTrue(after.contains("line 2\n"), "first hunk undone")
        XCTAssertTrue(after.contains("CHANGED 26"), "second hunk kept")
        XCTAssertEqual(GitDiff.load(repo: repo).files[0].hunks.count, 1)
    }

    func testRenamedHunkPatchIgnoresRenameAndStagedRevert() throws {
        let renamed = GitDiff.parse("""
        diff --git a/old.txt b/new.txt
        similarity index 90%
        rename from old.txt
        rename to new.txt
        index 1..2 100644
        --- a/old.txt
        +++ b/new.txt
        @@ -1,2 +1,2 @@
        -a
        +b
         c

        """)
        XCTAssertEqual(renamed[0].path, "new.txt")
        XCTAssertEqual(renamed[0].hunks[0].file, "new.txt")
        XCTAssertTrue(renamed[0].hunks[0].patch.hasPrefix("diff --git a/new.txt b/new.txt\n--- a/new.txt\n+++ b/new.txt\n@@"))

        // A staged change is undone in the index too, so it does not ride the next commit.
        let repo = NSTemporaryDirectory() + "oneroof-staged-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repo) }
        func git(_ a: String...) -> String { Foundations.run(GitDiff.git, ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t"] + a).1 }
        try "one\ntwo\n".write(toFile: repo + "/f.txt", atomically: true, encoding: .utf8)
        _ = git("init", "-q"); _ = git("add", "."); _ = git("commit", "-qm", "init")
        try "one\nTWO\n".write(toFile: repo + "/f.txt", atomically: true, encoding: .utf8)
        _ = git("add", "f.txt")
        let h = try XCTUnwrap(GitDiff.load(repo: repo).files.first?.hunks.first)
        XCTAssertNil(GitDiff.revert(h, repo: repo))
        XCTAssertEqual(git("diff", "--cached", "--name-only"), "", "staged change undone too")
        XCTAssertEqual(try String(contentsOfFile: repo + "/f.txt", encoding: .utf8), "one\ntwo\n")
        XCTAssertEqual(GitDiff.repoRoot(for: repo + "/f.txt").map { ($0 as NSString).lastPathComponent }, (repo as NSString).lastPathComponent)

        // A repo with no commits still names its branch.
        let fresh = repo + "/fresh"
        try FileManager.default.createDirectory(atPath: fresh, withIntermediateDirectories: true)
        _ = Foundations.run(GitDiff.git, ["-C", fresh, "init", "-q", "-b", "main"])
        try "x\n".write(toFile: fresh + "/a.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(GitDiff.stat(repo: fresh)?.branch, "main")
        XCTAssertEqual(GitDiff.stat(repo: fresh)?.files, 1)
    }

    func testNotARepo() {
        XCTAssertNil(GitDiff.repoRoot(for: NSTemporaryDirectory()))
        XCTAssertNil(GitDiff.repoRoot(for: NSTemporaryDirectory() + "no-such-folder-\(UUID().uuidString)"))
    }

    /// LAB-1327: repoRoot reads the file system (no git process) and must give what `git rev-parse --show-toplevel`
    /// gives: a subfolder and a file inside, a linked worktree (.git is a file), and a path through a symlink.
    func testRepoRootMatchesGitWithoutAProcess() throws {
        let base = NSTemporaryDirectory() + "rr-\(UUID().uuidString)"
        let repo = base + "/repo"
        try FileManager.default.createDirectory(atPath: repo + "/a/b", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        func git(_ dir: String, _ a: String...) -> String {
            Foundations.run(GitDiff.git, ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t"] + a).1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try "x\n".write(toFile: repo + "/a/b/f.txt", atomically: true, encoding: .utf8)
        _ = git(repo, "init", "-q"); _ = git(repo, "add", "."); _ = git(repo, "commit", "-qm", "init")
        let top = git(repo, "rev-parse", "--show-toplevel")
        XCTAssertEqual(GitDiff.repoRoot(for: repo), top)
        XCTAssertEqual(GitDiff.repoRoot(for: repo + "/a/b"), top)
        XCTAssertEqual(GitDiff.repoRoot(for: repo + "/a/b/f.txt"), top)
        _ = git(repo, "worktree", "add", "-q", base + "/wt")
        XCTAssertEqual(GitDiff.repoRoot(for: base + "/wt/a/b"), git(base + "/wt", "rev-parse", "--show-toplevel"))
        try FileManager.default.createSymbolicLink(atPath: base + "/link", withDestinationPath: repo + "/a")
        XCTAssertEqual(GitDiff.repoRoot(for: base + "/link/b"), git(base + "/link/b", "rev-parse", "--show-toplevel"))
    }
}
