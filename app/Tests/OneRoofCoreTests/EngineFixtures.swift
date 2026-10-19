import Foundation

/// Terminal snippets as each CLI prints them, shared by the caption and decision tests.
enum Fixture {
    static let claudeBashPrompt = """
    ⏺ The parser is in place. I'll run the caption tests to check the heuristics.

    ╭──────────────────────────────────────────────────────────────╮
    │ Bash command                                                 │
    │                                                              │
    │   swift test --filter CaptionTests                           │
    │   Run the caption tests                                      │
    │                                                              │
    │ Do you want to proceed?                                      │
    │ ❯ 1. Yes                                                     │
    │   2. Yes, and don't ask again for swift test commands in /Users/x/Projects/acme/web │
    │   3. No, and tell Claude what to do differently (esc)        │
    ╰──────────────────────────────────────────────────────────────╯
    """

    /// Claude Code 2.x draws the prompt without a box.
    static let claudePushPromptUnboxed = """
    ⏺ All tests pass. Pushing so CI can run the release build.

     Bash command

       git push origin work
       Push the live branch

     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and don't ask again for git push commands in /Users/x/Projects/acme/web
       3. No, and tell Claude what to do differently (esc)
    """

    static let claudeEditPrompt = """
    ⏺ Update(Sources/OneRoofCore/Feed.swift)

    ╭─────────────────────────────────────────────────────────────╮
    │ Edit file                                                   │
    │ ╭─────────────────────────────────────────────────────────╮ │
    │ │ Sources/OneRoofCore/Feed.swift                          │ │
    │ │                                                         │ │
    │ │ 12 -  public static let capacity = 100                  │ │
    │ │ 12 +  public static let capacity = 200                  │ │
    │ ╰─────────────────────────────────────────────────────────╯ │
    │ Do you want to make this edit to Feed.swift?                │
    │ ❯ 1. Yes                                                    │
    │   2. Yes, allow all edits during this session (shift+tab)   │
    │   3. No, and tell Claude what to do differently (esc)       │
    ╰─────────────────────────────────────────────────────────────╯
    """

    static let claudeFetchPrompt = """
    ⏺ I need the current herdr protocol notes. They're only published on the site.

    ╭──────────────────────────────────────────────╮
    │ Fetch                                        │
    │                                              │
    │   https://herdr.dev/docs/protocol            │
    │   Claude wants to fetch content from herdr.dev │
    │                                              │
    │ Do you want to allow Claude to fetch this content? │
    │ ❯ 1. Yes                                     │
    │   2. Yes, and don't ask again for herdr.dev  │
    │   3. No, and tell Claude what to do differently (esc) │
    ╰──────────────────────────────────────────────╯
    """

    static let codexPushPrompt = """
    • I need to push the branch so CI can run.

    Allow command?

      $ git push origin work

    › 1. Yes, proceed (y)
      2. Yes, and don't ask again for this command (a)
      3. No, and tell Codex what to do differently (esc)
    """

    static let codexEditPrompt = """
    • Ran cargo test
    • The config parser needs a default for the new field.

    Would you like to make the following edits?

      └ src/config.rs (+4 -1)

    › 1. Yes, proceed (y)
      2. Yes, and don't ask again for these files (a)
      3. No, and tell Codex what to do differently (esc)
    """

    static let kimiInstallPrompt = """
    • I'll install the requests library for the HTTP client.

    ╭─ Approval required ──────────────────────────╮
    │ Shell is requesting approval to run command: │
    │ pip install requests                         │
    │                                              │
    │ Allow?                                       │
    │ › 1. Approve once                            │
    │   2. Approve for this session                │
    │   3. Reject, tell Kimi what to do instead    │
    ╰──────────────────────────────────────────────╯
    """

    static let kimiInlinePrompt = """
    • Checking which files are large before I clean up.
    Shell: du -sh *
    Allow? [y]es / [a]lways for this session / [n]o
    """

    static let geminiDeletePrompt = """
    ✦ The build folder is stale, so I'll remove it before rebuilding.

    ╭──────────────────────────────────────────────╮
    │ ?  Shell rm -rf build (Remove the stale build folder) │
    │                                              │
    │ rm -rf build                                 │
    │                                              │
    │ Allow execution of: 'rm'?                    │
    │                                              │
    │ ● 1. Yes, allow once                         │
    │   2. Yes, allow always ...                   │
    │   3. No, suggest changes (esc)               │
    ╰──────────────────────────────────────────────╯
    """

    static let antigravityNetworkPrompt = """
    ● I'll fetch the dependency list from the registry first.

    Antigravity wants to run a command:
      `curl -s https://registry.npmjs.org/left-pad`

    Run this command? (y)es / (a)lways / (n)o
    """

    /// A Claude transcript: Task A (Explore) starts nested Task B (which edits a file) and finishes; Task C still runs
    /// and its entries carry no parentToolUseID (matched by parentUuid / order).
    static let transcript = """
    {"type":"user","uuid":"u1","parentUuid":null,"isSidechain":false,"timestamp":"2026-10-18T10:00:00.000Z","message":{"role":"user","content":"Build the engines"}}
    {"type":"assistant","uuid":"a1","parentUuid":"u1","isSidechain":false,"timestamp":"2026-10-18T10:00:05.000Z","message":{"role":"assistant","model":"claude-opus-4-1","content":[{"type":"tool_use","id":"toolu_A","name":"Task","input":{"description":"Explore the store","prompt":"Find how SessionStore migrates tables.","subagent_type":"Explore"}}],"usage":{"input_tokens":10,"output_tokens":20}}}
    {"type":"user","uuid":"s1","parentUuid":null,"isSidechain":true,"parentToolUseID":"toolu_A","timestamp":"2026-10-18T10:00:06.000Z","message":{"role":"user","content":"Find how SessionStore migrates tables."}}
    {"type":"assistant","uuid":"s2","parentUuid":"s1","isSidechain":true,"parentToolUseID":"toolu_A","timestamp":"2026-10-18T10:00:10.000Z","message":{"role":"assistant","model":"claude-haiku-4-5","content":[{"type":"text","text":"Looking at SessionStore."},{"type":"tool_use","id":"toolu_R","name":"Read","input":{"file_path":"/r/app/Sources/OneRoofCore/SessionStore.swift"}}],"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":25,"cache_read_input_tokens":9000}}}
    {"type":"assistant","uuid":"s3","parentUuid":"s2","isSidechain":true,"parentToolUseID":"toolu_A","timestamp":"2026-10-18T10:00:20.000Z","message":{"role":"assistant","model":"claude-haiku-4-5","content":[{"type":"tool_use","id":"toolu_B","name":"Task","input":{"description":"Patch the feed cap","prompt":"Raise the feed capacity to 200."}}],"usage":{"input_tokens":10,"output_tokens":5}}}
    {"type":"assistant","uuid":"b1","parentUuid":null,"isSidechain":true,"parentToolUseID":"toolu_B","timestamp":"2026-10-18T10:00:25.000Z","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"tool_use","id":"toolu_E","name":"Edit","input":{"file_path":"/r/app/Sources/OneRoofCore/Feed.swift","old_string":"cap = 100","new_string":"cap = 200\\n// raised"}}],"usage":{"input_tokens":40,"output_tokens":10}}}
    {"type":"user","uuid":"s4","parentUuid":"s3","isSidechain":true,"parentToolUseID":"toolu_A","timestamp":"2026-10-18T10:01:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B","content":"done"}]}}
    {"type":"user","uuid":"u2","parentUuid":"a1","isSidechain":false,"timestamp":"2026-10-18T10:02:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"Store uses CREATE IF NOT EXISTS."}]}}
    {"type":"assistant","uuid":"a2","parentUuid":"u2","isSidechain":false,"timestamp":"2026-10-18T10:02:05.000Z","message":{"role":"assistant","model":"claude-opus-4-1","content":[{"type":"tool_use","id":"toolu_C","name":"Task","input":{"description":"Write tests","prompt":"Write the caption fixtures."}}]}}
    {"type":"user","uuid":"c1","parentUuid":null,"isSidechain":true,"timestamp":"2026-10-18T10:02:06.000Z","message":{"role":"user","content":"Write the caption fixtures."}}
    {"type":"assistant","uuid":"c2","parentUuid":"c1","isSidechain":true,"timestamp":"2026-10-18T10:02:30.000Z","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Writing thirty fixtures now."}],"usage":{"input_tokens":7,"output_tokens":3}}}
    not json at all
    """
}
