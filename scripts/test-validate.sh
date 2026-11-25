#!/usr/bin/env bash
# Check that scripts/validate.sh fails the broken repositories it is meant to
# catch, with a message naming the problem, and passes the valid ones.
#
# Each case is a small repository built in a temporary folder: one good skill
# and a good marketplace manifest, with one thing changed. Nothing is written
# inside this repository.
set -uo pipefail

validate="$(cd "$(dirname "$0")" && pwd)/validate.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/test-validate.XXXXXX")"
trap 'rm -rf "$work"' EXIT

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

# A description of the given number of characters.
long_description() { printf '%*s' "$1" '' | tr ' ' 'x'; }

report() { # report <ok|FAILED> <case> <output>
  [ "$1" = ok ] || failures=$((failures + 1))
  printf '%-6s %s\n' "$1" "$2"
  printf '%s\n' "$3" | sed 's/^/         /'
}

# must_fail <case> <text>: validate.sh must exit 1 and print an error
# containing the text. A crash with a Ruby stack trace does not count.
must_fail() {
  local out status
  out="$("$validate" "$repo" 2>&1)"
  status=$?
  if [ "$status" -eq 1 ] && grep -F -- "$2" <<<"$out" | grep -q '^error: ' \
    && ! grep -qE 'Traceback|\(SyntaxError\)|^-:[0-9]+:' <<<"$out"; then
    report ok "fails: $1" "$(grep -F -- "$2" <<<"$out")"
  else
    report FAILED "fails: $1" "expected exit 1 and an error containing: $2
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
echo "with $(command -v ruby): $(ruby -ryaml -e 'print "ruby #{RUBY_VERSION}, YAML library psych #{Psych::VERSION}"' 2>&1)"
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
rm -r "$repo/skills/good-skill"
must_fail "no skills at all" 'no skills found under skills/'

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
name: other-skill
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name not matching its folder" 'skills/good-skill/SKILL.md: name "other-skill" does not match its folder name "good-skill"'

new_repo
rm -r "$repo/skills/good-skill"
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/Good_Skill"] }
  ]
}
JSON
write_skill Good_Skill <<'MD'
---
name: Good_Skill
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name with capitals and an underscore" 'name "Good_Skill" breaks the Agent Skills naming rules: it may only contain lowercase letters, digits and hyphens'

new_repo
rm -r "$repo/skills/good-skill"
write_manifest <<'JSON'
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/good--skill-"] }
  ]
}
JSON
write_skill good--skill- <<'MD'
---
name: good--skill-
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name with a doubled and a trailing hyphen" 'it must not start or end with a hyphen; it must not have two hyphens in a row'

new_repo
rm -r "$repo/skills/good-skill"
long_name="$(long_description 65)"
write_manifest <<JSON
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "plugins": [
    { "name": "example-skills", "source": "./", "skills": ["./skills/$long_name"] }
  ]
}
JSON
write_skill "$long_name" <<MD
---
name: $long_name
description: Does a thing. Use when the thing needs doing.
---
MD
must_fail "name over 64 characters" 'it is 65 characters and the limit is 64'

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
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when: the thing needs doing.
---
MD
must_fail "frontmatter that is not valid YAML (a colon inside an unquoted value)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 3: '

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing.
  metadata:
 version: "1.0"
---
MD
must_fail "frontmatter that is not valid YAML (bad indentation)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML'

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
if "$validate" "$repo" 2>&1 | grep -q '^note: '; then
  report FAILED "passes: all six uploadable keys give no note" "$("$validate" "$repo" 2>&1)"
else
  report ok "passes: all six uploadable keys give no note" "(no note printed)"
fi
cases=$((cases + 1))

# --- No YAML parser ---------------------------------------------------------

# Run validate.sh with a PATH that has no ruby on it. It must say so plainly.
new_repo
mkdir "$work/no-ruby"
ln -s "$(command -v dirname)" "$work/no-ruby/dirname"
out="$(PATH="$work/no-ruby" "$BASH" "$validate" "$repo" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && grep -qF 'error: validate.sh needs ruby' <<<"$out"; then
  report ok "fails: no ruby on the PATH" "$out"
else
  report FAILED "fails: no ruby on the PATH" "got exit $status and:
$out"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures of $cases cases FAILED"
  exit 1
fi
echo "all $cases cases behaved as expected"
