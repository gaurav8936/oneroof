# site/ · the One Roof launch page

The public page at https://gaurav8936.github.io/oneroof/. Plain HTML, CSS and one small script, no build step.
`.github/workflows/pages.yml` publishes this folder to GitHub Pages on every push to `main` that touches `site/`.

| File | What it is |
|---|---|
| `index.html` | the page (the released state is written into the HTML, so it works without JavaScript) |
| `assets/style.css` | layout and the three themes (Porcelain, Graphite, Blueprint) as CSS variables |
| `assets/site.js` | launch config, theme switcher, smooth anchors |
| `shots/` | app screenshots, `<view>-<daylight\|graphite\|midnight>.png` for the themed ones |
| `og.png` | social card, 1200×630 |
| `assets/favicon.png`, `assets/apple-touch-icon.png` | from `app/Resources/AppIcon.icns` |

## Preview locally

```bash
cd site && python3 -m http.server 3952
# open http://localhost:3952/   (add ?theme=graphite or ?theme=blueprint to force a theme)
```

## Launch config

At the top of `assets/site.js`:

```js
const LAUNCH = { released: true, version: '0.4.0', releaseDate: 'Tue 20 Oct 2026',
  downloadUrl: 'https://github.com/gaurav8936/oneroof/releases/latest/download/One-Roof-0.4.0.zip',
  repo: 'https://github.com/gaurav8936/oneroof', blogUrl: 'https://gabblegrid.ai/blog/one-workspace' };
```

For a new release, change `version` and `downloadUrl` there and the matching text in `index.html` (search for
`0.4.0`), so the page reads right with or without JavaScript. `released: false` switches the page to its
"launching soon" state (Star on GitHub, release date).

## Removing the Gatekeeper note

Once the app is signed and notarized, delete the one element marked `data-gatekeeper-note` in `index.html`
(install step 01). Nothing else refers to it.
