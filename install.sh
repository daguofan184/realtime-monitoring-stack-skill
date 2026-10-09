#!/usr/bin/env sh
# Install the realtime-monitoring-stack AI skills (Linux / macOS / WSL).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/daguofan184/realtime-monitoring-stack-skill/main/install.sh | sh
#   ./install.sh --scope project
#   ./install.sh --copy                 # copy instead of symlink
#   ./install.sh --uninstall
#
# Idempotent: safe to re-run, and re-running is how you update after a git pull.
set -eu

REPO_URL="https://github.com/daguofan184/realtime-monitoring-stack-skill.git"
CACHE_DIR="${HOME}/.dsh/skill-src/realtime-monitoring-stack-skill"

SCOPE="user"
TARGET=""
MODE="link"
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)     SCOPE="${2:-}"; shift 2 ;;
    --target)    TARGET="${2:-}"; shift 2 ;;
    --copy)      MODE="copy"; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- source
# Skills = direct subdirectories containing SKILL.md (discovery is one level deep).
# NOTE: this is used both to decide "are we already inside a clone?" and to build
# the install list, so it must not hardcode any skill name.
has_skills() {
  for d in "$1"/*/; do
    # `if`, not `[ ... ] && return 0`: the && form only survives here because the
    # function happens to be called from an `if !` (POSIX disables set -e inside
    # a function invoked in a condition). Do not rely on the caller.
    if [ -f "${d}SKILL.md" ]; then
      return 0
    fi
  done
  return 1
}

collect_skills() {
  SKILLS=""
  for d in "$1"/*/; do
    # `if`, not `[ ... ] && ...`: under `set -e` a failing test as the last
    # command of an && list aborts the whole script.
    if [ -f "${d}SKILL.md" ]; then
      SKILLS="${SKILLS} $(basename "$d")"
    fi
  done
}

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || pwd)"
if ! has_skills "$SRC"; then
  # Piped through sh, or run from elsewhere: use a stable cache clone.
  if [ -d "$CACHE_DIR/.git" ]; then
    echo "Updating $CACHE_DIR"
    git -C "$CACHE_DIR" pull --ff-only
  else
    mkdir -p "$(dirname -- "$CACHE_DIR")"
    echo "Cloning into $CACHE_DIR"
    git clone --depth 1 "$REPO_URL" "$CACHE_DIR"
  fi
  SRC="$CACHE_DIR"
fi
[ -d "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

collect_skills "$SRC"
[ -n "$SKILLS" ] || { echo "no <name>/SKILL.md found in $SRC" >&2; exit 1; }

# ---------------------------------------------------------------- target
case "$SCOPE" in
  user)    ROOT="${HOME}/.dsh/skills" ;;
  project) ROOT="$(pwd)/.dsh/skills" ;;
  custom)  [ -n "$TARGET" ] || { echo "--scope custom needs --target" >&2; exit 2; }
           ROOT="$TARGET" ;;
  *) echo "bad --scope: $SCOPE" >&2; exit 2 ;;
esac

echo
echo "Source : $SRC"
echo "Skills :$(printf ' %s' $SKILLS)"
echo "Target : $ROOT"
echo "Mode   : $MODE"

remove_dest() {
  # Never follow a symlink while deleting: rm -rf on a symlink to a directory
  # is fine, but we stay explicit so the real skill files can never be touched.
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ -L "$1" ]; then rm -f "$1"; else rm -rf "$1"; fi
}

if [ "$UNINSTALL" = "1" ]; then
  echo
  echo "Uninstalling"
  for s in $SKILLS; do
    if [ -e "$ROOT/$s" ] || [ -L "$ROOT/$s" ]; then
      remove_dest "$ROOT/$s"; echo "  removed  $s"
    else
      echo "  absent   $s"
    fi
  done
  echo
  echo "Done."
  exit 0
fi

# ---------------------------------------------------------------- install
mkdir -p "$ROOT"

echo
echo "Installing"
for s in $SKILLS; do
  dest="$ROOT/$s"
  remove_dest "$dest"
  if [ "$MODE" = "copy" ]; then
    cp -R "$SRC/$s" "$dest"
  else
    ln -s "$SRC/$s" "$dest"
  fi
  if [ -f "$dest/SKILL.md" ]; then echo "  $(printf '%-24s' "$s") OK"
  else echo "  $(printf '%-24s' "$s") FAILED"; fi
done

# ---------------------------------------------------------------- verify
echo
echo "Verify"
for s in $SKILLS; do
  f="$ROOT/$s/SKILL.md"
  if [ ! -f "$f" ]; then echo "  $(printf '%-24s' "$s") MISSING"; continue; fi
  name="$(grep -m1 '^name:' "$f" | sed 's/^name:[[:space:]]*//')"
  verdict=""
  [ "$name" = "$s" ] || verdict="name mismatch ($name)"
  grep -q '^description:' "$f" || verdict="${verdict}missing description"
  if head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf'; then verdict="${verdict} has BOM"; fi
  if [ -n "$verdict" ]; then echo "  $(printf '%-24s' "$s") WARN:$verdict"
  else echo "  $(printf '%-24s' "$s") frontmatter OK"; fi
done

echo
echo "Done."
echo
echo "  Start a NEW session in your AI tool and look for these in its skill catalog:"
for s in $SKILLS; do echo "    - $s"; done
echo
echo "  Not showing up? Check, in order:"
echo "    1. the tool actually supports skills (some presets/profiles do not)"
echo "    2. --scope project only applies to sessions started in this directory"
echo "    3. the link still resolves: test -f <root>/<name>/SKILL.md"
echo
