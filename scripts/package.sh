#!/usr/bin/env bash
# Zip each skill that the Claude apps will accept into dist/<name>.zip, for
# uploading under Customize > Skills. The skill folder is the top level of each
# archive (<name>/SKILL.md), which is the shape the apps expect.
#
# Usage: scripts/package.sh [repository]
#
# With no argument it packages the repository this script is in. Give a folder
# to package that one instead, which is how scripts/test-package.sh runs it.
#
# What goes in a zip is the skill as it is in the last commit (HEAD), written
# by git itself (git archive). So a zip holds only files tracked by git, never
# a file that was not committed, and a link is kept as a link and never
# followed. Packaging the same commit twice gives the same bytes. A skill with
# changes that are not committed is still packaged from the last commit, with
# a line saying so.
#
# It has to be run in a git checkout. From a downloaded source archive, which
# has no commits, it stops and says so.
#
# The apps reject an uploaded skill whose frontmatter has any top-level key
# outside six (name, description, license, compatibility, metadata and
# allowed-tools), so such a skill gets no zip. Neither does a skill that
# scripts/validate.sh finds an error in. Each is skipped with a line saying
# why, and that is not an error. This script does not look at frontmatter
# itself: it asks validate.sh about each skill, and a skill gets a zip exactly
# when validate.sh finds no error in it and prints no note for it.
#
# Needs git, and yq and jq for validate.sh. On macOS: brew install yq jq
#
# Written for macOS's own /bin/bash (3.2) as well as newer ones.
set -euo pipefail
export LC_ALL=C

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [repository]" >&2
  exit 2
fi

scripts="$(cd "$(dirname "$0")" && pwd)"
validate="$scripts/validate.sh"
root="${1:-$scripts/..}"

if [ ! -d "$root" ]; then
  echo "error: $root is not a folder" >&2
  exit 2
fi
root="$(cd -- "$root" && pwd -P)"
dist="$root/dist"

# --- The tools this script needs ---------------------------------------------

missing=0
for tool in yq jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "error: package.sh needs $tool, and there is no $tool on the PATH." >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "       On macOS, install both with: brew install yq jq" >&2
  exit 2
fi
if ! command -v git > /dev/null 2>&1; then
  echo "error: package.sh needs git, and there is no git on the PATH." >&2
  exit 2
fi

# --- The commit to package ----------------------------------------------------

not_a_checkout() {
  echo "error: package.sh packages the files of the last commit, so it has to be run in a git checkout of this repository." >&2
  echo "       $1" >&2
  echo "       Clone the repository with git and run it there. A downloaded source archive has no commits to package." >&2
  exit 2
}

top="$(git -C "$root" rev-parse --show-toplevel 2> /dev/null)" || not_a_checkout "$root is not in a git checkout."
top="$(cd -- "$top" && pwd -P)"
if [ "$top" != "$root" ]; then
  not_a_checkout "$root is a folder inside another git checkout ($top), not a checkout of its own."
fi
commit="$(git -C "$root" rev-parse --verify --quiet 'HEAD^{commit}' 2> /dev/null)" || not_a_checkout "The checkout at $root has no commits yet."

tmp="$(mktemp -d "${TMPDIR:-/tmp}/package.XXXXXX" 2> /dev/null)" || {
  echo "error: package.sh could not make a temporary folder in ${TMPDIR:-/tmp}" >&2
  exit 2
}
trap 'rm -rf "$tmp"' EXIT

rm -rf "$dist"
mkdir -p "$dist"

# The skill folders in the commit, one to a line. (A folder name with a line
# break in it is not supported, here or by validate.sh's naming rules.)
git -C "$root" -c core.quotepath=off ls-tree -d --name-only "$commit" skills/ > "$tmp/folders" 2> /dev/null || true

# A copy of the commit's skills/, for validate.sh to read, so that the decision
# is made about the same files that go in the zip.
mkdir "$tmp/commit"
if [ -s "$tmp/folders" ]; then
  if ! git -C "$root" archive --format=tar "$commit" skills | tar -x -f - -C "$tmp/commit" 2> "$tmp/tar-error"; then
    echo "error: package.sh could not read the files of the last commit ($(sed -e 1q "$tmp/tar-error" | cut -c 1-160))" >&2
    exit 2
  fi
fi

# Print why a skill gets no zip, or nothing if it gets one, by asking
# validate.sh about it.
skip_reason() {
  local name="$1" out status=0 errors count note
  out="$("$validate" --skill "$name" "$tmp/commit" 2>&1)" || status=$?
  if [ "$status" -gt 1 ]; then
    # validate.sh could not run, for example because the yq on the PATH is the
    # wrong one. Pass on what it said and stop.
    printf '%s\n' "$out" >&2
    exit 2
  fi
  errors="$(printf '%s\n' "$out" | sed -n 's/^error: //p')"
  note="$(printf '%s\n' "$out" | sed -n 's/^note: //p' | sed -e 1q)"
  if [ "$status" -ne 0 ] || [ -n "$errors" ]; then
    count="$(printf '%s\n' "$errors" | grep -c . || true)"
    if [ "$count" -eq 1 ]; then
      echo "validate.sh found a problem in it: $errors"
    else
      echo "validate.sh found $count problems in it: $(printf '%s\n' "$errors" | awk 'NR > 1 { printf "; " } { printf "%s", $0 } END { print "" }')"
    fi
  elif [ -n "$note" ]; then
    # The note reads "skills/<name> gets no upload zip, because <reason>".
    case "$note" in
      *", because "*) echo "${note#*, because }" ;;
      *) echo "validate.sh says: $note" ;;
    esac
  fi
}

found=0
while IFS= read -r folder; do
  name="${folder#skills/}"

  if [ -n "$(git -C "$root" status --porcelain -- ":(literal)skills/$name" 2> /dev/null)" ]; then
    echo "note: skills/$name has changes that are not committed. They are left out: what is packaged is the last commit."
  fi

  # Look the file up by its exact name, as validate.sh does.
  if [ -n "$(find "$tmp/commit/skills/$name" -maxdepth 1 -name SKILL.md 2> /dev/null)" ]; then
    found=$((found + 1))
  fi

  # skip_reason runs in a subshell, so its "exit 2" has to be passed on.
  reason="$(skip_reason "$name")" || exit $?
  if [ -n "$reason" ]; then
    echo "skipped $name: no zip, because $reason"
    continue
  fi

  # git writes the zip from the commit. Each file's time is the commit's time,
  # and TZ, the compression level and the line-ending setting are fixed here so
  # that they can't differ from one run or one machine to the next. .DS_Store
  # files are left out even if one was committed.
  (
    cd "$root/skills"
    TZ=UTC git -c core.autocrlf=false archive --format=zip -9 -o "$dist/$name.zip" "$commit" \
      ":(literal)$name" ':(exclude,glob)**/.DS_Store'
  )
  echo "packaged dist/$name.zip"

  git -C "$root" -c core.quotepath=off ls-tree -r "$commit" -- ":(literal)skills/$name" \
    | awk -F '\t' '$1 ~ /^120000 / { print substr($2, 8) }' \
    | while IFS= read -r link; do
      echo "note: dist/$name.zip holds $link as a link, not as the file it points to."
    done
done < "$tmp/folders"

# A skill folder that is in the working folder but not in the commit.
for dir in "$root"/skills/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if ! grep -qxF "skills/$name" "$tmp/folders"; then
    echo "skipped $name: no zip, because none of it is committed. Only committed files are packaged."
  fi
done

if [ "$found" -eq 0 ]; then
  echo "no skills found under skills/ in the last commit" >&2
  exit 1
fi
