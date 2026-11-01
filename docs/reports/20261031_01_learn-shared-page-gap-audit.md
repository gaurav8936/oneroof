# Learn: what the native screens had that the shared page lacked

**Status:** IN REVIEW · **Date:** 2026-10-31 · **Project:** LAB-ONEROOF-ENHANCEMENTS · **Linear:** LAB-1893 (then LAB-1894)

> **One line:** every behaviour the classic native Learn screens had and the shared Agentic Engineering page lacked is restored through the page's host bridge, so the classic screens can go (LAB-1894); two native fallbacks are not restored, with the reason below.

## Context

Since 1.9.31 / 1.9.32 Learn shows the shared Agentic Engineering page (the `ggae` embed every site shows), saved in the app at build (`app/scripts/learn-fetch.py`), served by `LearnShared` from `oneroof-learn://hub/…` and wired to One Roof through the page's `bridge` (`LearnSharedWeb.swift`). The classic native screens (`UI/V2/V2Learn*.swift`, the `v2Body` of `LearnView.swift`) stayed behind Settings › Learn › classic screens. The owner rule "Redesign never loses features" asks for an audit from code, old against new, and every gap restored before the old screens are removed. The list started from the LAB-1762 audit and was re-checked against the code of both sides on 2026-10-31.

## The gaps and how each is restored

The page does each of these **only when the host passes the bridge member**; the websites pass no bridge and behave exactly as before (embed tests "no bridge" cases). Embed tests: `zibajoon-app/web/src/atlas/ae/host.test.ts`. Swift tests: `app/Tests/OneRoofCoreTests/LearnSharedAppTests.swift`. Captures: test copies (`scripts/selftest-shot.sh`), checked by eye.

| # | Native screens had (code) | Shared page before | Restored by | Tests | Capture |
|---|---|---|---|---|---|
| 1 | In-app post reader: In this post, Part n of N · bands, date · minutes · Published / Scheduled, Open on the web ↗, body without the site-only `gg-` blocks and Links, previous / next in the series, Hear it on the band (`LearnPostReader`); links to other posts open in the reader | A post opened the browser | `bridge.post(slug)` → `/app/post/<slug>` (the post's Markdown, sections, canonical, status, a base URL for its images at `/app/post-file/…`); the embed's reader at `#ae/post/<slug>` (`post.tsx`); a `/blog/<slug>` link in the page opens the reader | host.test "(1)(2) … reader", "no bridge"; Swift `test_post_text_for_the_reader_and_its_files` | `#ae/post/agentic-engineering`: kicker, TOC, body, side band list |
| 1b | Live posts: the hub refreshed when Learn opens (`LearnBlogFeed`), "From the … blog · updated 10:42", offline "Try again" (`LearnPostsSource`, `LearnNoPosts`) | The list saved at build | `bridge.posts()` → `/app/posts` (hub cache, refreshed by `LearnBlogFeed` while Learn shows; the list saved at build when the cache is empty), a `posts` event on every refresh, `postsNote` line, `bridge.refreshPosts` for Try again | host.test "Writing lists the host posts…", "a posts event refreshes"; Swift `test_posts_merge…`, `test_posts_never_synced…`, `test_posts_note…` | Writing: "From the Zibajoon blog · updated 4:07 PM · plus your Learn folders" |
| 2 | Posts from Settings › Learn folders merged in (`LearnPosts.all`) | None | The same `/app/posts` list (folders first, a folder wins on a slug); Settings changes reload it | Swift `test_posts_merge_learn_folders…`; host.test lists a folder post | Writing with a Learn-folder post (ONEROOF_SELFTEST_LEARNFOLDERS) |
| 3 | Radio follows One Roof's player: tuned to what plays, ON AIR / PAUSED, time into the card, part n of m with the scene's kicker, progress bar, ▶ / ❚❚ toggles the player, speed key steps 0.75–2×, ⏭ plays on, a dial line plays (`LearnRadioPanel`, `LearnNowPlaying`); play buttons show and toggle the playing card (`LearnRoundPlay(playing:)`); the card header says Pause / Resume (`LearnCardActions`); the map rings the playing card | Display always PAUSED at 0:00 on the last card picked; speed key disabled; play buttons always ▶ | `bridge.subscribe` + a `player` event (`LearnSharedApp.nowPlaying`, at once on a change, the time at most once a second), `bridge.toggle`, `bridge.rate`; Radio, rows, lists, card header and map read it | host.test "(3) Radio follows…" ×3, "partLabel"; Swift `test_now_playing…`, `test_bridge_messages…`, `test_terminal_folder…_and_rates_cycle` | Radio with a card playing: ON AIR · 02 LOOPS, 0:07 / 6:23, part 1 of 23, Tasks |
| 4 | The Listen page follows the native player's scene (`LearnCardWeb.follow`: the page's scene dot, only when dots = clips); the page pauses when One Roof starts | Not followed | The embed's Listen clicks the frame's scene dot from the `player` event, retrying until the page has loaded (`useFollowScene`); the controller pauses the page when One Roof's player starts | host.test "Listen: the frame shows the scene…", "showScene leaves a page…" | Listen on scene 5 after Play from here, dot 5 lit |
| 5 | Transcript: a scene's number plays from there; the scene playing is marked (`LearnTranscript`) | Plain numbers | `bridge.play(slug, [], scene)`; the row of the playing scene is marked | host.test "Transcript: Play from here…"; Swift `test_bridge_messages_parse_play_with_scene…` | Transcript with scene 03 marked and the player on part 3 |
| 6 | By folder reads the deck folder on disk (`DeckFolders`), file previews (Markdown with its front-matter, code panel, "First 400 lines"), Open in Terminal (a new terminal session there), Use in a session for a skill, Show in Finder (`LearnFolderView`) | A tree built from the catalog (no files the catalog does not list), no previews, Show in Finder only | `bridge.folder(path)` → `/app/folder` (entries on disk, sizes), `bridge.file(path)` → `/app/file` (400 lines, cut flag, Markdown flag), `bridge.terminal(path)` (inside the deck only), Use in a session in the panel | host.test "(6) By folder reads the deck on disk"; Swift `test_folder…`, `test_file_preview…`, `test_terminal_folder…` | By folder with folders the catalog does not list, video.yaml previewed |
| 7 | In-page search used One Roof's ranking: every word in a card, else `bestCards` (LearnMatch, 12) | The embed's own keyword count | `bridge.search(q)` → `/app/search` (`LearnSharedApp.search`, the same two calls the native page made); the page's own ranking shows until the app answers | host.test "(7) search uses the host ranking"; Swift `test_search_every_word…` | "how do I run two agents in parallel": 12 of 176, the app's order in the panel |
| 8 | Programme Play also opened the programme (`LearnRadioLower`) | Played only | With a bridge, Play also opens the programme page | host.test "a programme's Play also opens the programme" | (Radio) |

### Not restored, and why

| Native piece | Why it is not restored |
|---|---|
| The native Listen fallback for a card without its own page (`LearnListen`: scene panel, diagram boxes, scene dots) and its Chapters list | Every card the shared page lists must have its page in the bundled deck: `learn-fetch.py` fails the build otherwise, so the fallback can never show. The card page itself carries its sections menu, diagram and scene dots. |
| The classic window's page list (`LearnView.pagesBody`, the older window, `ui2` off) | Not part of the classic Learn *screens* (`learnClassic`); it is the older window's Learn and stays as it is. |

## How the bridge works

- The host page (`LearnShared.hostPage`) builds the bridge: actions post to `window.webkit.messageHandlers.oneroofLearn` (parsed by `LearnBridgeMessage`), questions fetch `oneroof-learn://hub/app/…` (answered by `LearnSharedApp` from a snapshot the controller keeps current: the deck, the posts and their note), and the app pushes events with `oneroofLearnEmit({type: "player" | "posts"})`.
- An older embed ignores the new members; a newer embed in an older app finds no members and behaves like the websites. The order the two ship in therefore does not matter for safety; the features appear when both are in a build.

## Ship order

1. Zibajoon: the embed change (blog-kit `src/embed/ae/`) is merged and published by the hub (`/blog/embed/ggae.js`).
2. One Roof: the next build re-fetches the embed (`learn-fetch.py`); `tools/release-check.sh --learn` then shows the new embed's sha256 as the hub's current one.
3. Until then a One Roof build carries the bridge with the old embed: Learn looks and works as in 1.9.34.

Local verification before the hub has it: `docs/runbooks/20261031_01_learn-test-with-a-local-embed.md`.

## LAB-1894: the classic screens removed

- Removed: `UI/V2/V2LearnBand.swift`, `V2LearnCard.swift`, `V2LearnFolders.swift`, `V2LearnLibrary.swift`, `V2LearnPeople.swift`, `V2LearnRadio.swift`, the `v2Body` path of `LearnView.swift`, `AppModel.learnUsesShared`, `ONEROOF_LEARN_CLASSIC`, and Settings › Learn › **Learn: classic screens** (`AppSettings.learnClassic`). A settings file that still has `learnClassic` loads as before and the key is no longer written (`test_settings_old_learn_classic_key_is_ignored_and_dropped`). `LearnAudio` moved to `UI/LearnAudio.swift`. A build without the saved page (from source without the deck, or `ONEROOF_LEARN_SKIP=1`) now says "Learn is not in this build" instead of falling back.
- The classic screens' self-test hooks drive the shared page (`LearnSharedSelfTest`, tests in `LearnSharedSelfTestTests`): `ONEROOF_SELFTEST_LEARNMODE` (every place: radio, band, card and its tab, writing, post, path, library, search, folder, radiokey, radiochip; old `skills/…` folder paths map to `content/cards/…`), `RAILFOLDED`, `AUTOADVANCE=0`, `CARDENDED` (also `finish@`), `PAGECLICK`, `PAGEJS`. `scripts/ui2-screens.tsv` folder rows use the `content/cards/` paths. `PLAYCARD`, `PLAY`, `HOWDOI`, `LEARN=<title>` and the perf `learn` scenario never depended on the classic screens.
- Not moved: `ONEROOF_SELFTEST_ROLLTICK` (slowed the native roll-over countdown for a capture). The shared page's countdown has no speed setting and no capture, journey or perf scenario used it; a capture of the countdown is taken within its three seconds.
- Help: `docs/help/09_learn.md` describes the shared page only.
