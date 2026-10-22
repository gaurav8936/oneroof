#!/bin/bash
# stop-test-roofd.sh — stop roofd daemons and holders left behind by tests, CI runs and dev builds.
# Never touches the installed app's roofd (/Applications/One Roof.app) or the pid launchd runs for the roofd job.
#
#   stop-test-roofd.sh --check            read-only: list every roofd and say which ones are strays
#   stop-test-roofd.sh <folder>...        stop every roofd whose binary lives under <folder> (CI: this run's workspace)
#   stop-test-roofd.sh --ci-orphans       stop CI roofds whose Woodpecker workspace no longer exists (a run that died)
#   stop-test-roofd.sh --all-strays       stop every roofd that is not the installed app's
#
# Matches on the real executable path (ps comm), so a daemon started with a bare argv[0] is still placed correctly.
# A run's own daemons only: two Woodpecker pipelines (push + pull_request) share the Mac at the same time.
set -u

APP="/Applications/One Roof.app/"
JOB="gui/$(id -u)/io.github.gaurav8936.oneroof.roofd"
LAUNCHD_PID=$(launchctl print "$JOB" 2>/dev/null | awk '$1 == "pid" && $2 == "=" { print $3; exit }')
WORK_MARK="/woodpecker/work/"

# pid<TAB>path for every running roofd. launchd starts the job with a bare "roofd": resolve those through lsof.
list() {
  ps -axo pid=,comm= | awk '{ pid = $1; sub(/^ *[0-9]+ /, ""); if ($0 ~ /(^|\/)roofd$/) print pid "\t" $0 }' |
  while IFS="$(printf '\t')" read -r pid path; do
    case "$path" in /*) ;; *) path=$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | grep -m1 '/roofd$') ;; esac
    [ -n "$path" ] && printf '%s\t%s\n' "$pid" "$path"
  done
}

protected() {   # $1 pid, $2 path
  [ "$1" = "${LAUNCHD_PID:-}" ] && return 0
  case "$2" in "$APP"*) return 0 ;; esac
  return 1
}

# the Woodpecker workspace folder a CI binary lives in (…/woodpecker/work/<run>/), or nothing
ci_run_dir() { case "$1" in *"$WORK_MARK"*) echo "${1%%"$WORK_MARK"*}$WORK_MARK$(echo "${1#*"$WORK_MARK"}" | cut -d/ -f1)" ;; esac; }

stop() {   # pids...
  [ $# -eq 0 ] && { echo "stop-test-roofd: nothing to stop"; return 0; }
  kill "$@" 2>/dev/null
  for _ in 1 2 3 4 5 6; do
    alive=""; for p in "$@"; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && break; sleep 0.5
  done
  [ -n "$alive" ] && kill -9 $alive 2>/dev/null
  echo "stop-test-roofd: stopped $# roofd process(es)"
}

mode="${1:---check}"
pids=""
while IFS="$(printf '\t')" read -r pid path; do
  [ -z "$pid" ] && continue
  if protected "$pid" "$path"; then
    [ "$mode" = "--check" ] && echo "  keep   $pid  $path"
    continue
  fi
  case "$mode" in
    --check)       echo "  STRAY  $pid  $path" ;;
    --all-strays)  pids="$pids $pid" ;;
    --ci-orphans)  d=$(ci_run_dir "$path"); [ -n "$d" ] && [ ! -d "$d" ] && pids="$pids $pid" ;;
    -*)            echo "usage: $0 [--check | --ci-orphans | --all-strays | <folder>...]" >&2; exit 2 ;;
    *)             for f in "$@"; do f="${f%/}/"; case "$path" in "$f"*) pids="$pids $pid" ;; esac; done ;;
  esac
done <<EOF
$(list)
EOF

[ "$mode" = "--check" ] && exit 0
stop $pids
