#!/usr/bin/env python3
"""LAB-1834 · save the shared Learn page in the app: One Roof's Learn is the Agentic Engineering page every site shows (one copy,
served by the blog hub as the `ggae` embed). Each build fetches it and saves a local copy, so Learn works offline and picks up
changes with the next release.

    scripts/learn-fetch.py <deck folder> <out folder>      # called by scripts/bundle.sh right after the deck is bundled

Saves into <out folder> (Resources/agentic_engineering/learn/):
    ggae.js, ggae.css            the embed           GET <hub>/blog/embed/ggae.{js,css}
    catalog.json                 the cards           GET <hub>/ae/api/catalog?site=<site>
    cards/<slug>.json            each card's details GET <hub>/ae/api/card/<slug>
    posts.json                   the posts list      GET <hub>/blog/api/posts?site=<site>
    learn-manifest.json          hub, fetch time, edition, the deck commits, sha256 of the embed, counts

Fails (exit 1) when any fetch fails or comes back empty, when the catalog has no cards, or when a card page the catalog lists is
not in the bundled deck (it could not play offline).

Environment:
    ONEROOF_LEARN_HUB   the hub (default https://console.zibajoon.com)
    ONEROOF_LEARN_SITE  whose view of the catalog and posts to save (default zibajoon: the hub's own, the master layout; the hub
                        has no "oneroof" site and the app mounts the page as "oneroof" itself)
    ONEROOF_GGAE_DIR    a folder with ggae.js + ggae.css to use instead of the hub's (local test builds of an unshipped embed;
                        the manifest records it, and tools/package-app.sh refuses it for a release)
"""
import concurrent.futures
import datetime
import hashlib
import json
import os
import shutil
import sys
import urllib.parse
import urllib.request

HUB = os.environ.get("ONEROOF_LEARN_HUB", "https://console.zibajoon.com").rstrip("/")
SITE = os.environ.get("ONEROOF_LEARN_SITE", "zibajoon")
GGAE_DIR = os.environ.get("ONEROOF_GGAE_DIR", "")
UA = "OneRoof-build/learn-fetch"


def fail(msg: str) -> None:
    print(f"learn: FAIL {msg}", file=sys.stderr)
    sys.exit(1)


def get(path: str, tries: int = 3) -> bytes:
    url = HUB + path
    last = ""
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Cache-Control": "no-cache"})
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
                if r.status != 200:
                    last = f"HTTP {r.status}"
                    continue
                if not body:
                    last = "empty body"
                    continue
                return body
        except Exception as e:  # noqa: BLE001 - any network error is retried, then fails the build
            last = str(e)
    fail(f"{url}: {last}")
    return b""


def write(path: str, data: bytes) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def deck_path(url: str) -> str:
    """https://<cdn>/content/cards/x/x.html → content/cards/x/x.html ("" when not a deck URL)."""
    p = urllib.parse.urlparse(url).path.lstrip("/")
    return p if p.startswith("content/") else ""


def main(deck: str, out: str) -> int:
    if not os.path.isfile(os.path.join(deck, "content", "catalog.json")):
        fail(f"no deck at {deck}")
    tmp = out.rstrip("/") + ".partial"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)

    # 1. The embed: from the hub, or a local build (test builds only).
    if GGAE_DIR:
        js, css = (open(os.path.join(GGAE_DIR, f), "rb").read() for f in ("ggae.js", "ggae.css"))
        if not js or not css:
            fail(f"{GGAE_DIR}: ggae.js or ggae.css is empty")
        ggae_from = "local"
    else:
        js, css = get("/blog/embed/ggae.js"), get("/blog/embed/ggae.css")
        ggae_from = "hub"
    if b"GGAE" not in js:
        fail("ggae.js does not define GGAE")
    write(os.path.join(tmp, "ggae.js"), js)
    write(os.path.join(tmp, "ggae.css"), css)

    # 2. The catalog and the posts.
    q = urllib.parse.quote(SITE)
    cat_raw = get(f"/ae/api/catalog?site={q}")
    cat = json.loads(cat_raw)
    if not cat.get("counts", {}).get("cards"):
        fail("the hub's catalog has no cards")
    write(os.path.join(tmp, "catalog.json"), cat_raw)
    posts_raw = get(f"/blog/api/posts?site={q}")
    posts = json.loads(posts_raw).get("posts")
    if not isinstance(posts, list):
        fail("the hub's posts reply has no posts list")
    write(os.path.join(tmp, "posts.json"), posts_raw)

    # 3. Every card in the catalog: its page must be in the bundled deck (offline playback), its details saved.
    slugs, missing = set(), []

    def walk(v, key=None):
        if isinstance(v, dict):
            if "slug" in v and "url" in v and "scenes" in v:
                slugs.add(v["slug"])
                rel = deck_path(v["url"])
                if not rel or not os.path.isfile(os.path.join(deck, rel)):
                    missing.append(f'{v["slug"]} ({rel or v["url"]})')
                # LAB-1967: a card's deep dive must be in the deck too, or it would play from the web (or not at all offline).
                deep = v.get("deep")
                if isinstance(deep, dict) and deep.get("url"):
                    drel = deck_path(deep["url"])
                    if not drel or not os.path.isfile(os.path.join(deck, drel)):
                        missing.append(f'{v["slug"]} deep dive ({drel or deep["url"]})')
            for k, x in v.items():
                walk(x, k)
        elif isinstance(v, list):
            for x in v:
                walk(x)

    walk(cat)
    if missing:
        fail(f"{len(missing)} card page(s) the hub lists are not in the bundled deck, e.g. {', '.join(sorted(set(missing))[:5])}"
             " (bundle the deck commit the hub published)")

    def detail(slug: str):
        return slug, get(f"/ae/api/card/{urllib.parse.quote(slug)}")

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for slug, body in ex.map(detail, sorted(slugs)):
            json.loads(body)  # must be JSON
            write(os.path.join(tmp, "cards", f"{slug}.json"), body)

    # 4. The manifest.
    ref = ""
    try:
        ref = open(os.path.join(deck, ".deck-ref")).read().split()[-1]
    except (OSError, IndexError):
        pass
    manifest = {
        "hub": HUB, "site": SITE, "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "edition": cat.get("edition"), "version": cat.get("version"), "catalogFrom": cat.get("from"), "deckRef": ref or None,
        "ggaeSha256": hashlib.sha256(js).hexdigest(), "ggaeCssSha256": hashlib.sha256(css).hexdigest(), "ggaeFrom": ggae_from,
        "cards": cat["counts"]["cards"], "cardDetails": len(slugs), "posts": len(posts),
    }
    write(os.path.join(tmp, "learn-manifest.json"), (json.dumps(manifest, indent=2) + "\n").encode())

    shutil.rmtree(out, ignore_errors=True)
    os.replace(tmp, out)
    src = str(cat.get("from") or "").split()[-1:] or [""]
    note = "" if not ref or not src[0] or src[0].startswith(ref) or ref.startswith(src[0]) else \
        f" (note: hub catalog from {cat.get('from')}, deck {ref})"
    print(f"learn: saved the shared page from {HUB} (embed from {ggae_from}, sha256 {manifest['ggaeSha256'][:12]}), "
          f"{manifest['cards']} cards, {len(slugs)} card details, {len(posts)} posts, edition {cat.get('edition')}{note}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
