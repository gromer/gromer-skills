#!/usr/bin/env bash
# What scripts/test-validate.sh and scripts/test-package.sh share: the
# temporary folder the cases are built in, a good small repository to start
# each case from, and the line that reports a case. It is read in with
# "source", not run.

work="$(mktemp -d "${TMPDIR:-/tmp}/test-skills.XXXXXX")" || {
  echo "error: $(basename "$0") could not make a temporary folder in ${TMPDIR:-/tmp}" >&2
  exit 1
}
trap '[ -z "$work" ] || rm -rf "$work"' EXIT

cases=0
failures=0
repo=""

# Start a case: a repository with one good skill, listed in a good manifest.
new_repo() {
  cases=$((cases + 1))
  repo="$work/case-$cases"
  mkdir -p "$repo/.claude-plugin"
  write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "strict": false, "skills": ["./skills/good-skill"] }
  ]
}
JSON
  write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
---

# Good skill
MD
}

# Replace the manifest, or a skill's SKILL.md, with the text on standard input.
write_manifest() { cat > "$repo/.claude-plugin/marketplace.json"; }
write_skill() {
  mkdir -p "$repo/skills/$1"
  cat > "$repo/skills/$1/SKILL.md"
}

# Replace the manifest with one that is good apart from its "plugins", which
# are given as JSON.
write_plugins() {
  write_manifest <<JSON
{ "name": "example-skills", "owner": { "name": "Example Owner" }, "plugins": $1 }
JSON
}

# The one good plugin entry, as JSON.
good_plugin='{ "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }'

# Replace the good skill with one in the given folder, named after its folder,
# and list it in the manifest.
rename_skill() {
  rm -r "$repo/skills/good-skill"
  write_plugins "[{ \"name\": \"example-skills\", \"source\": \"./\", \"skills\": [\"./skills/$1\"] }]"
  write_skill "$1" <<MD
---
name: $1
description: Does a thing. Use when the thing needs doing.
---
MD
}

# A description of the given number of characters.
long_description() { printf '%*s' "$1" '' | tr ' ' 'x'; }

report() { # report <ok|FAILED> <case> <output>
  [ "$1" = ok ] || failures=$((failures + 1))
  printf '%-6s %s\n' "$1" "$2"
  printf '%s\n' "$3" | sed 's/^/         /'
}
