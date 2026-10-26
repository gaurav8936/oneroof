# agentic_engineering

What One Roof bundles for agentic engineering. Since 1.9.0 One Roof authors **no** agentic-engineering content: every
skill, narrated card, Learn band, the course and the hooks live in the Agentic Engineering deck's own repository, and
every build packages that repository as it is on `main` into the app (`app/scripts/bundle.sh`, `ONEROOF_AE_DECK_REPO`).

```
scripts/     sync-skills.sh (links the deck's skills into every agent) · check.sh (release check)
deck/        added at build time, inside the app only: skills/, content/ (catalog, field manual, course/), hooks/
```

One Roof's own routing rules (`routing.json`, `roles.json`) are app configuration in `app/Resources/agent-routing/`;
copies in `~/.config/oneroof/agent-routing/` win.

## Use it

```bash
agentic_engineering/scripts/sync-skills.sh --dry-run   # shows the links it would make
agentic_engineering/scripts/sync-skills.sh             # links every deck skill into each agent's skills folder
```

Only deck skills are linked, so nothing in the app can win over the deck on a name clash; links to skills that are gone
are removed. A real folder, or a link to someone's own copy of a skill, is never replaced.

## Which folder One Roof reads

1. the `ONEROOF_AE_PATH` environment variable, if set (for development, e.g. a checkout of the deck repository);
2. this bundled copy (inside the app, or next to it in a source checkout).

## Change a skill, a lesson or a hook

Change it in the deck repository and merge it to `main`; the next One Roof build carries it.
