# Test Learn with a local embed build

**Status:** LIVE · **Date:** 2026-10-31 · **Project:** LAB-ONEROOF-ENHANCEMENTS · **Linear:** LAB-1893

> **One line:** to see an unpublished change to the shared Agentic Engineering page in One Roof, build the `ggae` embed locally, bundle a test copy with `ONEROOF_GGAE_DIR` pointing at it, and capture it with `scripts/selftest-shot.sh`; releases never take a local embed.

## When

A change to the shared Learn page (the Zibajoon `ggae` embed, `blog-kit/src/embed/ae/` in the Zibajoon app) has to be checked inside One Roof before the hub publishes it. Production builds always fetch the hub's embed; nothing here changes that.

## Steps

1. **Build the embed** in the Zibajoon checkout: `node scripts/blog/build-embed.mjs` writes `dist/blog/embed/ggae.{js,css}`. Its tests: `npx vitest run web/src/atlas/ae`.
2. **Bundle a One Roof test copy** with that embed (from `app/`, with `ONEROOF_AE_DECK_REPO` set to the deck checkout as for any build):

   ```sh
   ONEROOF_GGAE_DIR=<zibajoon checkout>/dist/blog/embed bash scripts/bundle.sh debug
   ```

   `learn-fetch.py` saves the local embed instead of the hub's and records `"ggaeFrom": "local"` in `learn-manifest.json`; the catalog, card details and posts still come from the hub. `tools/package-app.sh` refuses a build with `ONEROOF_GGAE_DIR` set, and `tools/release-check.sh --learn` fails on `ggaeFrom` other than `hub`.
3. **Or point an existing build at another saved page:** `ONEROOF_LEARN_DIR=<folder with ggae.js, ggae.css, catalog.json, posts.json, cards/, learn-manifest.json>` (the manifest's sha256 must match `ggae.js`).
4. **Capture** with the test copy only (scratch store, its own roofd; the installed One Roof and the owner's profile are never touched). Set `ONEROOF_BLOG_CACHE` to a scratch folder so the hub's posts are not written to the owner's cache:

   ```sh
   OUT_DIR=<scratch>/shots bash scripts/selftest-shot.sh learn-radio ONEROOF_SELFTEST_UI2=1 ONEROOF_SELFTEST_FOCUS=0 \
     ONEROOF_SELFTEST_LEARN=1 ONEROOF_BLOG_CACHE=<scratch>/blog ONEROOF_SELFTEST_PLAYCARD=loops-first@muted \
     ONEROOF_SELFTEST_LEARNHASH='#ae/radio' ONEROOF_SELFTEST_WAIT=6
   ```

   Hooks for the shared page: `ONEROOF_SELFTEST_LEARNHASH=#ae/<screen>` (where it opens), `ONEROOF_SELFTEST_LEARNJS=<s>@<js>[;;<s>@<js>…]` (scripts run that many seconds after the page mounted, e.g. `oneroofLearnSearch('…')` or a row click), `ONEROOF_SELFTEST_LEARNFOLDERS=<dir>[:<dir>]` (Settings › Learn folders for the run, never saved).
5. **Look at every capture** before calling it done.

## Shipping order

The embed reaches One Roof only after the hub publishes it and a One Roof build re-fetches it: Zibajoon first (merge, the hub serves the new `ggae.js`), then the One Roof build. A One Roof build made earlier shows the old embed, which ignores the new bridge members.
