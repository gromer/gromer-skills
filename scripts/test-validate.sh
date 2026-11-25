#!/usr/bin/env bash
# Check that scripts/validate.sh fails the broken repositories it is meant to
# catch, with a message naming the problem, and passes the valid ones.
#
# Each case is a small repository built in a temporary folder: one good skill
# and a good marketplace manifest, with one thing changed. Nothing is written
# inside this repository.
set -uo pipefail

validate="$(cd "$(dirname "$0")" && pwd)/validate.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/test-validate.XXXXXX")" || {
  echo "error: test-validate.sh could not make a temporary folder in ${TMPDIR:-/tmp}" >&2
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

# must_fail <case> <text> [problems]: validate.sh must exit 1 and print an
# error containing the text. It must report that many problems in all, one if
# no number is given, so a case can't pass on some other error. A raw error
# from bash, jq or yq does not count.
must_fail() {
  local out status
  out="$("$validate" "$repo" 2>&1)"
  status=$?
  if [ "$status" -eq 1 ] && grep -F -- "$2" <<<"$out" | grep -q '^error: ' \
    && grep -qF "validation failed: ${3:-1} problem(s)" <<<"$out" \
    && ! grep -qE '^jq: |^Error: |line [0-9]+: .*(command not found|syntax error|unbound variable)' <<<"$out"; then
    report ok "fails: $1" "$(grep -F -- "$2" <<<"$out")"
  else
    report FAILED "fails: $1" "expected exit 1, ${3:-1} problem(s), and an error containing: $2
got exit $status and:
$out"
  fi
}

# must_pass <case> [text]: validate.sh must exit 0 with no error, and print the
# text if one is given.
must_pass() {
  local out status
  out="$("$validate" "$repo" 2>&1)"
  status=$?
  if [ "$status" -eq 0 ] && ! grep -q 'error' <<<"$out" && grep -qF -- "${2:-ok: }" <<<"$out"; then
    report ok "passes: $1" "$(grep -F -- "${2:-ok: }" <<<"$out")"
  else
    report FAILED "passes: $1" "expected exit 0 and: ${2:-ok: }
got exit $status and:
$out"
  fi
}

echo "Testing $validate"
echo "with yq:   $(command -v yq): $(yq --version 2>&1 | head -n 1)"
echo "     jq:   $(command -v jq): $(jq --version 2>&1 | head -n 1)"
echo "     bash: $(command -v bash): $(bash --version | head -n 1)"
echo

# --- The marketplace manifest -----------------------------------------------

new_repo
must_pass "a good repository" "ok: 1 skill(s), manifest in sync"

new_repo
write_manifest <<'JSON'
{
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace name deleted" '.claude-plugin/marketplace.json has no "name"'

new_repo
write_manifest <<'JSON'
{
  "name": 7,
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace name is a number" '"name" must be text, but it is a number (7)'

new_repo
write_manifest <<'JSON'
{
  "name": "",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace name empty" '.claude-plugin/marketplace.json: "name" is empty'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace owner deleted" '.claude-plugin/marketplace.json has no "owner"'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "email": "owner@example.com" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace owner.name deleted" '"owner" has no "name"'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace owner.name empty" '"owner": "name" is empty'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": "Example Owner",
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "marketplace owner is text, not an object" '"owner" must be an object with a "name", but it is text'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "source": "./", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "plugin name deleted" 'plugin 1 has no "name"'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "plugin source deleted" 'plugin 1 ("example-skills") has no "source"'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": 123, "skills": ["./skills/good-skill"] }
  ]
}
JSON
must_fail "plugin source: 123" 'plugin 1 ("example-skills"): "source" must be a path such as "./", or an object saying where to fetch the plugin from, but it is a number (123)'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] },
    { "name": "elsewhere", "source": { "repo": "example/elsewhere" } }
  ]
}
JSON
must_fail "plugin source object that doesn't name its kind" 'plugin 2 ("elsewhere"): its "source" object must name its kind'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] },
    { "name": "elsewhere", "source": { "source": "github", "repo": "example/elsewhere" } }
  ]
}
JSON
must_pass "plugin source as an object (a GitHub repository)"

new_repo
write_plugins "[$good_plugin, { \"name\": 5, \"source\": \"./\" }]"
must_fail "plugin name is a number" 'plugin 2: "name" must be text, but it is a number (5)'

new_repo
write_plugins "[$good_plugin, { \"name\": \"elsewhere\", \"source\": \"\" }]"
must_fail "plugin source empty" 'plugin 2 ("elsewhere"): "source" is empty'

new_repo
write_plugins "[$good_plugin, { \"name\": \"elsewhere\", \"source\": \"./\", \"skills\": 5 }]"
must_fail "plugin skills is a number, not a list" 'plugin 2 ("elsewhere"): "skills" must be a list of paths'

new_repo
write_plugins "[$good_plugin, \"elsewhere\"]"
must_fail "plugin entry is text, not an object" 'plugin 2 must be an object, but it is text'

new_repo
write_manifest <<'JSON'
{ "name": "example-skills", "owner": { "name": "Example Owner" } }
JSON
must_fail "plugins list deleted" '.claude-plugin/marketplace.json has no "plugins" list'

new_repo
write_plugins '{ "example-skills": "./" }'
must_fail "plugins is an object, not a list" '"plugins" must be a list, but it is an object'

new_repo
write_manifest <<'JSON'
["example-skills"]
JSON
must_fail "manifest is a list, not an object" '.claude-plugin/marketplace.json must be a JSON object, but it is a list'

new_repo
: > "$repo/.claude-plugin/marketplace.json"
must_fail "manifest is an empty file" '.claude-plugin/marketplace.json must hold one JSON object'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill"] },
  ]
}
JSON
must_fail "manifest is not valid JSON" '.claude-plugin/marketplace.json is not valid JSON'

new_repo
{ printf '\357\273\277'; cat "$repo/.claude-plugin/marketplace.json"; } > "$work/with-mark.json"
mv "$work/with-mark.json" "$repo/.claude-plugin/marketplace.json"
must_pass "manifest that starts with a byte-order mark"

new_repo
write_plugins '[{ "name": "example-skills", "source": "./", "skills": "skills/good-skill/" }]'
must_pass "skills given as one path, with no ./ and a trailing slash"

new_repo
rm "$repo/.claude-plugin/marketplace.json"
must_fail "manifest missing" '.claude-plugin/marketplace.json was not found'

# --- The manifest and the folders under skills/ agree ------------------------

new_repo
write_skill second-skill <<'MD'
---
name: second-skill
description: Does another thing. Use when that needs doing.
---
MD
must_fail "skill missing from the manifest" 'skills/second-skill is not listed in .claude-plugin/marketplace.json'

new_repo
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good-skill", "./skills/gone-skill"] }
  ]
}
JSON
must_fail "manifest lists a skill that isn't there" '.claude-plugin/marketplace.json lists skills/gone-skill, which has no SKILL.md'

new_repo
mkdir -p "$repo/skills/empty-folder/references"
must_fail "folder with no SKILL.md" 'skills/empty-folder has no SKILL.md'

new_repo
mv "$repo/skills/good-skill/SKILL.md" "$repo/skills/good-skill/skill.md"
must_fail "skill.md in lower case" 'skills/good-skill has no SKILL.md'

new_repo
rm -r "$repo/skills/good-skill"
must_fail "no skills at all" 'no skills found under skills/' 2

new_repo
write_plugins '[{ "name": "example-skills", "source": "./", "skills": ["./skills/good-skill", "./skills/second-skill"] }]'
write_skill second-skill <<'MD'
---
name: second-skill
description: ""
---
MD
must_fail "a good first skill and a broken second one" 'skills/second-skill/SKILL.md: description is empty'

# --- SKILL.md frontmatter ---------------------------------------------------

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: ""
---
MD
must_fail 'description: ""' 'skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description:
---
MD
must_fail "description with nothing after it" 'skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: "   "
---
MD
must_fail "description of only spaces" 'skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
---
MD
must_fail "description missing" 'skills/good-skill/SKILL.md has no description in its frontmatter'

new_repo
write_skill good-skill <<'MD'
---
name: ""
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name empty" 'skills/good-skill/SKILL.md: name is empty'

new_repo
write_skill good-skill <<'MD'
---
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name missing" 'skills/good-skill/SKILL.md has no name in its frontmatter'

new_repo
write_skill good-skill <<'MD'
---
name: [good-skill]
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name that is a list" 'skills/good-skill/SKILL.md: name must be text, not a list or nested keys'

new_repo
write_skill good-skill <<'MD'
---
name: other-skill
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name not matching its folder" 'skills/good-skill/SKILL.md: name "other-skill" does not match its folder name "good-skill"'

new_repo
rename_skill Good-Skill
must_fail "name with capital letters" 'name "Good-Skill" breaks the Agent Skills naming rules: it may only contain lowercase letters (a-z), digits and hyphens'

new_repo
rename_skill good_skill
must_fail "name with an underscore" 'name "good_skill" breaks the Agent Skills naming rules: it may only contain lowercase letters (a-z), digits and hyphens'

new_repo
rename_skill café
must_fail "name with a letter outside a-z" 'name "café" breaks the Agent Skills naming rules: it may only contain lowercase letters (a-z), digits and hyphens'

new_repo
rename_skill -good-skill
must_fail "name that starts with a hyphen" 'name "-good-skill" breaks the Agent Skills naming rules: it must not start or end with a hyphen'

new_repo
rename_skill good-skill-
must_fail "name that ends with a hyphen" 'name "good-skill-" breaks the Agent Skills naming rules: it must not start or end with a hyphen'

new_repo
rename_skill good--skill
must_fail "name with two hyphens in a row" 'name "good--skill" breaks the Agent Skills naming rules: it must not have two hyphens in a row'

new_repo
rename_skill "$(long_description 65)"
must_fail "name over 64 characters" 'breaks the Agent Skills naming rules: it is 65 characters and the limit is 64'

new_repo
rename_skill "$(long_description 64)"
must_pass "name of exactly 64 characters"

new_repo
rename_skill 2048
must_pass "name that is all digits"

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: $(long_description 1025)
---
MD
must_fail "description over 1024 characters" 'skills/good-skill/SKILL.md: description is 1025 characters and the limit is 1024'

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: $(long_description 1024)
---
MD
must_pass "description of exactly 1024 characters"

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: $(long_description 1024 | sed 's/x/é/g')
---
MD
must_pass "description of 1024 accented characters (2048 bytes)"

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: $(long_description 1025 | sed 's/x/é/g')
---
MD
must_fail "description of 1025 accented characters" 'skills/good-skill/SKILL.md: description is 1025 characters and the limit is 1024'

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: >
  $(long_description 1024)
---
MD
must_pass "description of 1024 characters written with >, which adds a line break"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.

# Good skill
MD
must_fail "unclosed frontmatter" 'skills/good-skill/SKILL.md: the frontmatter is never closed'

new_repo
write_skill good-skill <<'MD'
# Good skill

Does a thing.
MD
must_fail "no frontmatter" 'skills/good-skill/SKILL.md has no frontmatter: its first line must be ---'

new_repo
: > "$repo/skills/good-skill/SKILL.md"
must_fail "SKILL.md is an empty file" 'skills/good-skill/SKILL.md has no frontmatter: its first line must be ---'

new_repo
printf -- '---\n---\n\n# Good skill\n' > "$repo/skills/good-skill/SKILL.md"
must_fail "frontmatter with nothing in it" 'skills/good-skill/SKILL.md: the frontmatter is empty'

new_repo
printf '\357\273\277---\nname: good-skill\ndescription: Does a thing.\n---\n' > "$repo/skills/good-skill/SKILL.md"
must_fail "SKILL.md that starts with a byte-order mark" 'skills/good-skill/SKILL.md starts with a byte-order mark'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when: the thing needs doing.
---
MD
must_fail "frontmatter that is not valid YAML (a colon inside an unquoted value)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML ('

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing.
  metadata:
 version: "1.0"
---
MD
must_fail "frontmatter that is not valid YAML (bad indentation)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML ('

new_repo
write_skill good-skill <<'MD'
---
- good-skill
- Does a thing.
---
MD
must_fail "frontmatter that is a list, not keys" "skills/good-skill/SKILL.md: the frontmatter must be 'key: value' lines"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
description: Does it again.
---
MD
must_fail "the same key twice" 'skills/good-skill/SKILL.md: the frontmatter has "description" more than once'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description:
  - Does a thing.
  - Use when the thing needs doing.
---
MD
must_fail "description that is a list" 'skills/good-skill/SKILL.md: description must be text, not a list or nested keys'

# --- Valid frontmatter that the old sed-based check got wrong ----------------

new_repo
write_skill good-skill <<'MD'
---
name: "good-skill"
description: Does a thing. Use when the thing needs doing.
---
MD
must_pass 'quoted name ("good-skill")'

new_repo
write_skill good-skill <<'MD'
---
name: 'good-skill'
description: 'Does a thing. Use when the thing needs doing.'
---
MD
must_pass "single-quoted name and description"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: >
  Does a thing.
  Use when the thing needs doing.
---
MD
must_pass "multi-line description, folded (>)"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: |
  Does a thing.
  Use when the thing needs doing.
---
MD
must_pass "multi-line description, literal (|)"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description:
  Does a thing.
  Use when the thing needs doing.
---
MD
must_pass "multi-line description, continued on the next lines"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: "Does a thing.
  Use when: the thing needs doing."
---
MD
must_pass "multi-line description, quoted"

new_repo
printf -- '---\r\nname: good-skill\r\ndescription: Does a thing.\r\n---\r\n\r\n# Good skill\r\n' > "$repo/skills/good-skill/SKILL.md"
must_pass "Windows line endings"

# --- Keys the Claude apps reject: a note, not an error ----------------------

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
disable-model-invocation: true
---
MD
must_pass "frontmatter keys outside the six give a note" 'note: skills/good-skill gets no upload zip, because the Claude apps reject these frontmatter keys: argument-hint, disable-model-invocation'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
license: MIT
compatibility: Needs git.
metadata:
  author: example
  version: "1.0"
allowed-tools: Read Grep
---
MD
must_pass "all six uploadable keys, with nested metadata"
out="$("$validate" "$repo" 2>&1)"
cases=$((cases + 1))
if grep -q '^note: ' <<<"$out"; then
  report FAILED "passes: all six uploadable keys give no note" "$out"
else
  report ok "passes: all six uploadable keys give no note" "(no note printed)"
fi

# --- yq or jq missing, or the wrong yq ----------------------------------------

# Run validate.sh with a PATH that holds only the tools named, as links. It
# must stop with exit 2 and say plainly what is wrong and how to get the tools,
# before checking anything. "other-yq" stands for the other tool called yq, the
# Python one, which answers --version the way that one does.
tool_case() { # tool_case <case> <text> <tool>...
  local name="$1" text="$2" bin out status tool
  shift 2
  new_repo
  bin="$work/bin-$cases"
  mkdir "$bin"
  for tool in dirname "$@"; do
    if [ "$tool" = other-yq ]; then
      printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$bin/yq"
      chmod +x "$bin/yq"
    else
      ln -s "$(command -v "$tool")" "$bin/$tool"
    fi
  done
  out="$(PATH="$bin" "$BASH" "$validate" "$repo" 2>&1)"
  status=$?
  if [ "$status" -eq 2 ] && grep -qF -- "$text" <<<"$out" && grep -qF 'brew install yq' <<<"$out" \
    && ! grep -q 'command not found' <<<"$out"; then
    report ok "stops: $name" "$out"
  else
    report FAILED "stops: $name" "expected exit 2, a brew install line and: $text
got exit $status and:
$out"
  fi
}

tool_case "no yq on the PATH" 'error: validate.sh needs yq, and there is no yq on the PATH.' jq
tool_case "no jq on the PATH" 'error: validate.sh needs jq, and there is no jq on the PATH.' yq
tool_case "the other yq (the Python one)" 'This one says: yq 3.4.3' jq other-yq

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures of $cases cases FAILED"
  exit 1
fi
echo "all $cases cases behaved as expected"
