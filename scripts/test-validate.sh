#!/usr/bin/env bash
# Check that scripts/validate.sh fails the broken repositories it is meant to
# catch, with a message naming the problem, and passes the valid ones.
#
# Each case is a small repository built in a temporary folder: one good skill
# and a good marketplace manifest, with one thing changed. Nothing is written
# inside this repository.
set -uo pipefail

validate="$(cd "$(dirname "$0")" && pwd)/validate.sh"
# shellcheck source=scripts/test-helpers.sh
source "$(dirname "$0")/test-helpers.sh"

# Run validate.sh on the case's repository. Set with_locale to run it in that
# locale, for the cases that must not depend on one.
with_locale=""
run_validate() {
  if [ -n "$with_locale" ]; then
    LC_ALL="$with_locale" "$validate" "$repo" 2>&1
  else
    "$validate" "$repo" 2>&1
  fi
}

# The lines of validate.sh's output that are not its own. Every line it prints
# starts with "error: ", "note: ", "ok: " or "validation failed: ". Anything
# else is a raw message from bash, jq or yq reaching the reader.
foreign_lines() { grep -vE '^(error: |note: |ok: |validation failed: )' <<<"$1"; }

# must_fail <case> <text> [problems]: validate.sh must exit 1 and print an
# error containing the text. It must report that many problems in all, one if
# no number is given, so a case can't pass on some other error.
must_fail() {
  local out status
  out="$(run_validate)"
  status=$?
  if [ "$status" -eq 1 ] && grep -F -- "$2" <<<"$out" | grep -q '^error: ' \
    && grep -qF "validation failed: ${3:-1} problem(s)" <<<"$out" \
    && [ -z "$(foreign_lines "$out")" ]; then
    report ok "fails: $1" "$(grep -F -- "$2" <<<"$out")"
  else
    report FAILED "fails: $1" "expected exit 1, ${3:-1} problem(s), only validate.sh's own lines, and an error containing: $2
got exit $status and:
$out"
  fi
}

# must_pass <case> [text]: validate.sh must exit 0 with no error, and print the
# text if one is given.
must_pass() {
  local out status
  out="$(run_validate)"
  status=$?
  if [ "$status" -eq 0 ] && ! grep -qE '^(error|validation failed): ' <<<"$out" \
    && [ -z "$(foreign_lines "$out")" ] && grep -qF -- "${2:-ok: }" <<<"$out"; then
    report ok "passes: $1" "$(grep -F -- "${2:-ok: }" <<<"$out")"
  else
    report FAILED "passes: $1" "expected exit 0, only validate.sh's own lines, and: ${2:-ok: }
got exit $status and:
$out"
  fi
}

# must_print_no_note <case>: validate.sh must print no note.
must_print_no_note() {
  local out
  out="$(run_validate)"
  cases=$((cases + 1))
  if grep -q '^note: ' <<<"$out"; then
    report FAILED "passes: $1" "$out"
  else
    report ok "passes: $1" "(no note printed)"
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
write_manifest <<JSON
{ "name": null, "owner": { "name": "Example Owner" }, "plugins": [$good_plugin] }
JSON
must_fail "marketplace name is null" '.claude-plugin/marketplace.json: "name" must be text, but it is null'

new_repo
write_manifest <<JSON
{ "name": false, "owner": { "name": "Example Owner" }, "plugins": [$good_plugin] }
JSON
must_fail "marketplace name is false" '.claude-plugin/marketplace.json: "name" must be text, but it is false'

new_repo
printf '{ "name": "example\377", "owner": { "name": "Example Owner" }, "plugins": [%s] }\n' "$good_plugin" > "$repo/.claude-plugin/marketplace.json"
must_fail "manifest with a byte that is not UTF-8" '.claude-plugin/marketplace.json is not UTF-8 text'

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
write_manifest <<JSON
{ "name": "example-skills", "owner": { "name": 7 }, "plugins": [$good_plugin] }
JSON
must_fail "marketplace owner.name is a number" '"owner": "name" must be text, but it is a number (7)'

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
write_plugins "[$good_plugin, { \"name\": \"\", \"source\": \"./\" }]"
must_fail "plugin name empty" 'plugin 2: "name" is empty'

new_repo
write_plugins "[$good_plugin, { \"name\": \"elsewhere\", \"source\": \"\" }]"
must_fail "plugin source empty" 'plugin 2 ("elsewhere"): "source" is empty'

new_repo
write_plugins "[$good_plugin, { \"name\": \"elsewhere\", \"source\": null }]"
must_fail "plugin source is null" 'plugin 2 ("elsewhere"): "source" must be a path such as "./", or an object saying where to fetch the plugin from, but it is null'

new_repo
write_plugins "[$good_plugin, { \"name\": \"elsewhere\", \"source\": false }]"
must_fail "plugin source is false" 'plugin 2 ("elsewhere"): "source" must be a path such as "./", or an object saying where to fetch the plugin from, but it is false'

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
write_plugins '"example-skills"'
must_fail "plugins is text, not a list" '"plugins" must be a list, but it is text'

new_repo
write_plugins '["example-skills"]'
must_fail "plugins is a list of text, with no plugin entry" 'plugin 1 must be an object, but it is text' 2

new_repo
write_manifest <<'JSON'
[1, 2]
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
must_fail "manifest is not valid JSON (a comma after the last plugin), with the place" '.claude-plugin/marketplace.json is not valid JSON (parse error: Expected another array element at line 6, column 3)'

# jq takes these as numbers, and JSON does not. Claude Code rejects them.
for number in 007 .5 +1 1. NaN Infinity; do
  new_repo
  write_manifest <<JSON
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "metadata": { "description": "Example", "n": $number },
  "plugins": [$good_plugin]
}
JSON
  must_fail "manifest with $number, which is not a JSON number" '.claude-plugin/marketplace.json is not valid JSON'
done

new_repo
write_manifest <<JSON
{
  "name": "example-skills",
  "owner": { "name": "Example Owner" },
  "metadata": { "description": "Example", "n": [7, -0, 1e5, 1E+2, 0.5] },
  "plugins": [$good_plugin]
}
JSON
must_pass "manifest with numbers JSON does allow"

new_repo
rm "$repo/.claude-plugin/marketplace.json"
ln -s nowhere.json "$repo/.claude-plugin/marketplace.json"
must_fail "manifest that is a link to a file that isn't there" '.claude-plugin/marketplace.json could not be read'

new_repo
{ printf '\357\273\277'; cat "$repo/.claude-plugin/marketplace.json"; } > "$work/with-mark.json"
mv "$work/with-mark.json" "$repo/.claude-plugin/marketplace.json"
must_pass "manifest that starts with a byte-order mark"

new_repo
write_plugins '[{ "name": "example-skills", "source": "./", "skills": "./skills/good-skill" }]'
must_pass "skills given as text, not a list"

new_repo
write_plugins '[{ "name": "example-skills", "source": "./", "skills": ["skills/good-skill/"] }]'
must_pass "skills path with no ./ and a trailing slash"

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
description: ~
---
MD
must_fail "description: ~" 'skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: null
---
MD
must_fail "description: null" 'skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: "null"
---
MD
must_pass 'description: "null", which is the word as text'

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
with_locale=C
must_fail "name with a letter outside a-z, run with LC_ALL=C" 'name "café" breaks the Agent Skills naming rules: it may only contain lowercase letters (a-z), digits and hyphens'
with_locale=""
cases=$((cases + 1))

new_repo
rename_skill "my skill"
must_fail "folder and name with a space, read as one skill" 'skills/my skill/SKILL.md: name "my skill" breaks the Agent Skills naming rules: it may only contain lowercase letters (a-z), digits and hyphens'

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

# Names made of digits and lowercase letters that YAML reads as a number or as
# no value when they have no quotes. The message must say so and give the fix,
# not show a name the person never wrote.
for name in 007 1e3 0x10 12345678901234567890123; do
  new_repo
  rename_skill "$name"
  must_fail "name $name without quotes, which YAML reads as a number" "skills/$name/SKILL.md: name is read by YAML as a number, not as text, so it does not match its folder name \"$name\". If the name is right, put it in quotes: name: \"$name\""
done

new_repo
rename_skill null
must_fail "name null without quotes, which YAML reads as no value" 'skills/null/SKILL.md: name is read by YAML as no value, not as text, so it does not match its folder name "null". If the name is right, put it in quotes: name: "null"'

new_repo
rename_skill 007
write_skill 007 <<'MD'
---
name: "007"
description: Does a thing. Use when the thing needs doing.
---
MD
must_pass 'name "007" in quotes'

new_repo
rename_skill true
must_pass "name true, which reads the same as text"

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
with_locale=C
must_pass "description of 1024 accented characters, run with LC_ALL=C"
with_locale=""
cases=$((cases + 1))

new_repo
write_skill good-skill <<MD
---
name: good-skill
description: $(long_description 1025 | sed 's/x/é/g')
---
MD
must_fail "description of 1025 accented characters" 'skills/good-skill/SKILL.md: description is 1025 characters and the limit is 1024'
with_locale=C
must_fail "description of 1025 accented characters, run with LC_ALL=C" 'skills/good-skill/SKILL.md: description is 1025 characters and the limit is 1024'
with_locale=""
cases=$((cases + 1))

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
write_skill good-skill <<MD
---
name: good-skill
description: |
  $(long_description 1024)
---
MD
must_pass "description of 1024 characters written with |, which adds a line break"

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
# The same again in a UTF-8 locale, where some tools count the mark as one
# character and not three bytes. Skipped if this machine has no such locale.
with_locale="$(locale -a 2> /dev/null | grep -iE '^(C|en_US)\.utf-?8$' | sed -n 1p)"
if [ -n "$with_locale" ]; then
  cases=$((cases + 1))
  must_fail "SKILL.md that starts with a byte-order mark, run with LC_ALL=$with_locale" 'skills/good-skill/SKILL.md starts with a byte-order mark'
fi
with_locale=""

new_repo
rm "$repo/skills/good-skill/SKILL.md"
ln -s nowhere.md "$repo/skills/good-skill/SKILL.md"
must_fail "SKILL.md that is a link to a file that isn't there" 'skills/good-skill/SKILL.md could not be read'

new_repo
rm "$repo/skills/good-skill/SKILL.md"
mkdir "$repo/skills/good-skill/SKILL.md"
must_fail "SKILL.md that is a folder" 'skills/good-skill/SKILL.md could not be read'

# Taking away read permission stops nobody who runs as root, so these three are
# skipped there. Permission is given back afterwards so the folder can be
# cleaned up.
if [ "$(id -u)" -ne 0 ]; then
  new_repo
  chmod 000 "$repo/skills/good-skill/SKILL.md"
  must_fail "SKILL.md with no read permission" 'skills/good-skill/SKILL.md could not be read'
  chmod 644 "$repo/skills/good-skill/SKILL.md"

  new_repo
  chmod 000 "$repo/skills/good-skill"
  must_fail "skill folder with no read permission" 'skills/good-skill could not be read'
  chmod 755 "$repo/skills/good-skill"

  new_repo
  chmod 000 "$repo/.claude-plugin/marketplace.json"
  must_fail "manifest with no read permission" '.claude-plugin/marketplace.json could not be read'
  chmod 644 "$repo/.claude-plugin/marketplace.json"
fi

# A repository in a folder whose name starts with a dash, given by that name.
new_repo
mkdir "$work/dash-$cases"
mv "$repo" "$work/dash-$cases/-r"
cd "$work/dash-$cases" || exit 1
repo="-r"
must_pass "repository folder called -r" "ok: 1 skill(s), manifest in sync"
cd "$OLDPWD" || exit 1

new_repo
printf -- '---\nname: good-skill\ndescription: Does a thing.\n---\n\nCaf\351.\n' > "$repo/skills/good-skill/SKILL.md"
must_fail "SKILL.md with a byte that is not UTF-8" 'skills/good-skill/SKILL.md is not UTF-8 text'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when: the thing needs doing.
---
MD
must_fail "frontmatter that is not valid YAML (a colon inside an unquoted value)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 3: mapping values are not allowed in this context)'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing.
  metadata:
 version: "1.0"
---
MD
must_fail "frontmatter that is not valid YAML (bad indentation)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 4: '

# The next three are worded by yq with a clause in brackets and a range of
# places ("L3.C14-L4.C1"), which validate.sh turns into a line number.
new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: "Does a thing.
---
MD
must_fail "frontmatter that is not valid YAML (a missing closing quote)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 3: '

new_repo
printf -- '---\nname: good-skill\ndescription: Does a thing.\n\tmetadata: x\n---\n' > "$repo/skills/good-skill/SKILL.md"
must_fail "frontmatter that is not valid YAML (a tab used to indent)" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 3: '

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing.
allowed-tools: [Read, Grep
---
MD
must_fail "frontmatter that is not valid YAML (a missing ])" 'skills/good-skill/SKILL.md: the frontmatter is not valid YAML (line 4: '

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
must_print_no_note "all six uploadable keys give no note"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
---

# Good skill

---

argument-hint: x

---

More.
MD
must_pass "--- rules further down the file, with a key-like line between them"
must_print_no_note "--- rules further down the file give no note"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: |
  Does a thing.
  argument-hint: x
---
MD
must_pass "a key-like line inside a | block"
must_print_no_note "a key-like line inside a | block gives no note"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
"my key": x
"*": x
metadata:x: y
---
MD
must_pass "keys with a space, a star and a colon in them are each named whole" 'because the Claude apps reject these frontmatter keys: my key, *, metadata:x'

# scripts/package.sh makes a zip for a skill with any of these four keys,
# because it cuts a key at its first colon and strips a quote mark from either
# end. Each is outside the six, so validate.sh must give the note.
new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
metadata:x: y
license:mit: yes
metadata": y
"license: x": y
---
MD
must_pass "keys that only look like one of the six" 'because the Claude apps reject these frontmatter keys: metadata:x, license:mit, metadata", license: x'

# Text from a SKILL.md must never be run. If it were, a file called marker
# would appear in the folder validate.sh is run from.
new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: "$(touch marker) `touch marker`"
"$(touch marker) `touch marker`": x
---
MD
cd "$repo" || exit 1
must_pass "shell commands in a description and a key are treated as text" 'because the Claude apps reject these frontmatter keys: $(touch marker) `touch marker`'
cd "$OLDPWD" || exit 1
cases=$((cases + 1))
if [ -n "$(find "$work" -name marker)" ]; then
  report FAILED "passes: no command from a SKILL.md was run" "found: $(find "$work" -name marker)"
else
  report ok "passes: no command from a SKILL.md was run" "(no marker file was made)"
fi

# --- yq or jq missing, or the wrong yq ----------------------------------------

# Run validate.sh with a PATH that holds only the tools named, as links. It
# must stop with exit 2 and say plainly what is wrong and how to get the tools,
# before checking anything, in lines that start "error: " or carry one on. "other-yq" stands for the other tool called yq, the
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
    && ! grep -qvE '^(error: |       )' <<<"$out"; then
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
