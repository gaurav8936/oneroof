// One Roof launch page: launch state, theme switcher (Porcelain · Graphite · Blueprint), smooth anchors.
// No framework, no build step. The HTML already holds the released state, so the page works without JavaScript.

// ---- Launch config: edit here, then push. ----
const LAUNCH = {
  released: true,
  version: '0.5.1.1',
  releaseDate: 'Fri 23 Oct 2026',
  downloadUrl: 'https://github.com/gaurav8936/oneroof/releases/latest/download/One-Roof-0.5.1.1.zip',
  repo: 'https://github.com/gaurav8936/oneroof',
  blogUrl: 'https://gabblegrid.ai/blog/one-workspace',
};

// Which app screenshot goes with each page theme (file names in shots/).
const SHOT_THEME = { porcelain: 'daylight', graphite: 'graphite', blueprint: 'midnight' };
const THEMES = Object.keys(SHOT_THEME);
const THEME_BG = { porcelain: '#f6f6f3', graphite: '#111214', blueprint: '#0b2a5b' };

function launchText() {
  const v = 'v' + LAUNCH.version, d = LAUNCH.releaseDate;
  return LAUNCH.released
    ? { statusText: `${v} is out · free and open source`, headerCta: 'DOWNLOAD', heroCta: 'Download for Mac', closeCta: 'Download for Mac (.zip)',
        heroCtaNote: `${v} · .zip`, secondaryCta: 'View on GitHub', stepCta: 'DOWNLOAD .ZIP' }
    : { statusText: `Launching ${d} · star the repo to hear when it's out`, headerCta: 'STAR ON GITHUB', heroCta: 'Star on GitHub', closeCta: 'Star on GitHub',
        heroCtaNote: `out ${d}`, secondaryCta: 'Take the tour', stepCta: `AVAILABLE ${d.toUpperCase()}` };
}

function applyLaunch() {
  const t = launchText();
  const href = {
    primary: LAUNCH.released ? LAUNCH.downloadUrl : LAUNCH.repo,
    secondary: LAUNCH.released ? LAUNCH.repo : '#tour',
    blog: LAUNCH.blogUrl,
  };
  document.querySelectorAll('[data-launch-text]').forEach(el => {
    const k = el.getAttribute('data-launch-text');
    if (t[k] != null) el.textContent = t[k];
  });
  document.querySelectorAll('[data-launch-href]').forEach(el => {
    const k = el.getAttribute('data-launch-href');
    if (href[k]) el.setAttribute('href', href[k]);
  });
  document.querySelectorAll('.status').forEach(el => el.classList.toggle('pre', !LAUNCH.released));
}

function currentTheme() {
  const t = document.documentElement.getAttribute('data-theme');
  return THEMES.includes(t) ? t : 'porcelain';
}

function applyTheme(name, save) {
  if (!THEMES.includes(name)) name = 'porcelain';
  document.documentElement.setAttribute('data-theme', name);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute('content', THEME_BG[name]);
  document.querySelectorAll('[data-theme-btn]').forEach(b =>
    b.setAttribute('aria-pressed', String(b.getAttribute('data-theme-btn') === name)));
  const st = SHOT_THEME[name];
  document.querySelectorAll('img[data-shot]').forEach(img => {
    const src = `shots/${img.getAttribute('data-shot')}-${st}.png`;
    if (img.getAttribute('src') !== src) img.setAttribute('src', src);
  });
  if (save) { try { localStorage.setItem('oneroof-theme', name); } catch (e) { /* private mode: no memory, still works */ } }
}

function smoothAnchors() {
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.addEventListener('click', e => {
    const a = e.target.closest && e.target.closest('a[href^="#"]');
    if (!a) return;
    const id = a.getAttribute('href').slice(1);
    const el = id && document.getElementById(id);
    if (!el) return;
    e.preventDefault();
    el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    history.replaceState(null, '', '#' + id);
  });
}

document.addEventListener('DOMContentLoaded', () => {
  applyLaunch();
  applyTheme(currentTheme(), false);
  document.querySelectorAll('[data-theme-btn]').forEach(b =>
    b.addEventListener('click', () => applyTheme(b.getAttribute('data-theme-btn'), true)));
  smoothAnchors();
});
