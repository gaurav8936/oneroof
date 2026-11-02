#!/usr/bin/env bash
# LAB-2164 · Neutral words in the Agentic Engineering deck that goes inside One Roof.app.
#   scripts/deck-neutral.sh <deck-folder>
# The deck repository is the author's own working kit, so its skills name the author's login, e-mail, live branch and
# key folder. The copy packaged for the public download gets neutral stand-ins instead; the repository (and the author's
# own linked skills) stay as they are. Stand-ins keep scripts valid: a branch stays a branch name ("you/live"), a folder
# a folder name. Product names (GabbleGrid, Agencium, Hypothesys) are public and stay. Text files only.
set -euo pipefail
DECK="${1:?usage: deck-neutral.sh <deck-folder>}"
[ -d "$DECK" ] || { echo "deck-neutral: no folder $DECK" >&2; exit 1; }
LOGIN="$(id -un)"
EMAIL_USER="$(git config user.email 2>/dev/null | cut -d@ -f1 || true)"
export LOGIN EMAIL_USER
PATTERN="$LOGIN|ganarasi|access_admin|internal\.agencium\.com${EMAIL_USER:+|${EMAIL_USER//./\\.}@}"
n=0
while IFS= read -r -d '' f; do
  grep -qIE "$PATTERN" "$f" 2>/dev/null || continue
  perl -pi -e '
    my $l = quotemeta $ENV{LOGIN};
    s{/Users/$l\b}{~}g;                 # home paths
    s{-Users-$l-}{-Users-you-}g;          # Claude project folder names
    s{\b$l\b}{you}g;
    if (length $ENV{EMAIL_USER}) { my $e = quotemeta $ENV{EMAIL_USER}; s{\b$e\@[A-Za-z0-9.-]+}{you\@example.com}g; s{\b$e\@}{you\@}g; }
    s{ganarasi}{you}g;                    # the live branch: ganarasi/live -> you/live
    s{access_admin}{secrets}g;            # the key-file folder
    s{[A-Za-z0-9.-]*internal\.agencium\.com}{ai-gateway.example.com}g;
  ' "$f"
  n=$((n + 1))
done < <(find "$DECK" -type f \( -name '*.md' -o -name '*.txt' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \
           -o -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.toml' -o -name '*.html' -o -name '*.css' \
           -o -name '*.csv' -o -name '*.jsonl' -o -name '*.tsv' -o -name '*.cfg' -o -name '*.ini' -o -name '*.svg' \) -print0)
left="$(grep -rlIE "$PATTERN" "$DECK" 2>/dev/null || true)"
echo "deck-neutral: $n file(s) given neutral words${left:+; still named in: $(echo "$left" | wc -l | tr -d ' ') file(s), e.g. ${left%%$'\n'*}}"
[ -z "$left" ]
