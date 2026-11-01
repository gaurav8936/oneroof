# One Roof 2.0.3: secrets and public-repo audit

**Status:** done (fixes in review) · **Date:** 2026-11-01 · **Workstream:** LAB-ONEROOF-v2.0.3 (LAB-2140)

> **One line:** no key, token or private key anywhere in the public repo's history, the 2.0.0 download or the 2.0.1
> candidate; the only leaks are workspace folder names, and the ones in One Roof's own code are removed.

## What was scanned

| Target | How | Result |
|---|---|---|
| Full git history, every ref (482 refs, 1,066 commits, 28 MB of patches) | gitleaks 8.30.1 (`git --log-opts=--all`) | 16 hits, all false positives: `UserDefaults` key names (`forKey: "v2.focusColumnWidth."`) |
| Same history | own pattern sweep: Anthropic, OpenAI, OpenRouter, Fireworks, Daytona, Replicate, Hugging Face, Linear, Slack, GitHub, AWS, Google keys, PEM private keys, the notary key id and issuer | 0 hits |
| Tracked tree at HEAD | `tools/release-check.sh` | clean |
| Published `One-Roof-2.0.0.zip` (GitHub Latest) | SHA-256 against the published `.sha256`; `release-check.sh --zip`; key sweep over all 6,410 files | checksum matches; release-check clean; 0 keys |
| 2.0.1 candidate bundle | `release-check.sh --app`; key sweep | 0 keys |

## Findings

| # | Finding | Severity | Action |
|---|---|---|---|
| 1 | The executables (app and roofd) held three dev-machine paths from the legacy settings migration: two help folders of another product and the workspace data folder's model path. `release-check --app` missed them: it only looks for absolute home paths, and these are built from the home folder at run time. | Medium (names, no secret) | **Fixed:** the migration no longer fills in workspace folders (Settings and on-disk discovery cover both); a test keeps the file free of them; `release-check --app` now fails on workspace names in the executables. |
| 2 | The packaged Agentic Engineering deck (about 100 files, from its own private repo) names the owner's login in example paths, the start of the owner's e-mail address, the owner's live-branch name and the key-file folder's name. | Medium (the deck repo is private, but its content ships publicly in the app) | Filed as its own issue for the deck repo; `release-check --app` reports it as a warning until the deck is clean, then it can be made a failure. |
| 3 | Older commits in the public history name workspace folders and the file name of the Pages deploy key (never its value). | Low | No rewrite (it would break every clone and every release tag); owner decision recorded in the go/no-go. |
| 4 | 140 merged `lift/*` branches are still on the public remote (the process deletes them after merge). | Low (hygiene) | Owner decision: deleting remote branches is an outward push. |
| 5 | The release notes mention another product's name once (an old entry). | Low | Left as is (history of the changelog). |

## How to check

```sh
gitleaks git --log-opts="--all" --redact .       # 16 hits, all forKey: names
tools/release-check.sh                           # clean
tools/release-check.sh --app "<candidate>/One Roof.app"   # FAIL on 2.0.1 (finding 1), ok after this fix; warn line = finding 2
swift test --filter 'LegacyMigrationTests|NeutralSourceTests'   # in app/
```
