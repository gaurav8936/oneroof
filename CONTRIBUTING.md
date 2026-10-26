# Contributing

One Roof is early. The most useful help right now is **trying it on your Mac and telling us what broke**.

## Report what you find

Open an issue with the bug-report template. The most helpful details are your Mac and macOS version, what you did,
and the output of `"/Applications/One Roof.app/Contents/MacOS/OneRoof" --check` (remove anything private first).
Confusing wording, a setup step you got stuck on, or an agent that is not detected all count.

## Build and test

```bash
brew install herdr zig@0.15            # plus Xcode 26 with the Metal Toolchain
cd app && scripts/build-ghosttykit.sh  # once: builds libghostty outside the repo
swift build && swift test              # OneRoofCore + app tests
scripts/bundle.sh                      # → app/build/One Roof.app
OneRoof --fresh-profile                # run as a brand-new user: setup window, empty settings
bash tests/run.sh                      # the kit's sandboxed test suite (from the repo root)
bash agentic_engineering/scripts/check.sh
bash tools/terminal-basics.sh          # real app: drag-select, copy, paste in a herdr terminal
```

## Pull requests

- One change per pull request, with a test when it changes behaviour (see `app/Tests/`, `tests/`).
- Keep it neutral: no personal paths, account names or company-specific names in code, docs or screenshots.
  `tools/release-check.sh` and the guard tests in `app/Tests/OneRoofCoreTests/NeutralTests.swift` check this.
- UI changes: include a screenshot taken in demo mode (`app/scripts/selftest-shot.sh <name> ONEROOF_SELFTEST_DEMO=1`).
- Skills, cards and hooks are not written here: they live in the Agentic Engineering deck's own repository,
  which the app packages at build time. `agentic_engineering/` holds only the linking script and its check.

## Licence

By contributing you agree that your contribution is licensed under the repository's MIT licence.
