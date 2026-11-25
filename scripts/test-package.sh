#!/usr/bin/env bash
# Check that scripts/package.sh makes a zip for the skills it should and no
# others, that a zip holds only committed files, and that packaging the same
# commit twice gives the same bytes.
#
# Each case is a small git repository built in a temporary folder, as in
# scripts/test-validate.sh. Nothing is written inside this repository.
set -uo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
package="$scripts/package.sh"
validate="$scripts/validate.sh"
# shellcheck source=scripts/test-helpers.sh
source "$scripts/test-helpers.sh"

# git, for building the cases: without the settings of whoever runs the tests,
# and with a fixed author and date, so that a case's commit is the same commit
# on every machine.
case_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME="Example Owner" GIT_AUTHOR_EMAIL="owner@example.com" \
    GIT_COMMITTER_NAME="Example Owner" GIT_COMMITTER_EMAIL="owner@example.com" \
    GIT_AUTHOR_DATE="2026-01-02T03:04:05Z" GIT_COMMITTER_DATE="2026-01-02T03:04:05Z" \
    git -C "$repo" -c init.defaultBranch=main -c core.autocrlf=false "$@"
}

# Commit everything in the case's repository, ignored files too.
commit_all() {
  [ -d "$repo/.git" ] || case_git init -q . > /dev/null 2>&1
  case_git add -A -f . && case_git commit -q --allow-empty -m "A case for test-package.sh" > /dev/null
}

# Run package.sh on the case's repository. Leaves what it printed in $out and
# its exit status in $status.
out=""
status=0
pack() {
  out="$("$package" "$repo" 2>&1)"
  status=$?
}

# In the conditions below, a command's output is read whole and then searched
# (grep ... <<<"$(command)"), never piped to "grep -q": grep -q stops reading at
# its first match, which under pipefail can fail the pipe by accident.

# The names in a zip, one to a line.
zip_names() { unzip -Z1 "$1" 2> /dev/null; }

# The zips in the case's dist/, as names on one line.
zips() { (cd "$repo/dist" 2> /dev/null && ls) | tr '\n' ' ' | sed 's/ $//'; }

checksum() { cksum < "$1"; }

# What validate.sh says the skill should get: "zip" if it finds no error in the
# skill and prints no note for it, and "no zip" otherwise.
validate_says() {
  local said
  if said="$("$validate" "$repo" 2>&1)" && ! grep -q "^note: skills/$1 " <<<"$said"; then
    echo "zip"
  else
    echo "no zip"
  fi
}

# check <case> <condition> <detail>: report the case as ok if the condition (a
# command) holds. The condition is run here, so it can't use $1, $2 and so on.
check() {
  if eval "$2"; then
    report ok "$1" "$3"
  else
    report FAILED "$1" "this did not hold: $2
package.sh exit $status and:
$out
dist/ holds: $(zips)"
  fi
}

# gets_zip <case>: validate.sh and package.sh must both say the good skill gets
# a zip, and the zip must have the skill folder at its top level.
gets_zip() {
  commit_all
  pack
  check "zip: $1" \
    '[ "$status" -eq 0 ] && [ "$(validate_says good-skill)" = zip ] && [ "$(zips)" = good-skill.zip ] \
      && grep -qx "good-skill/SKILL.md" <<<"$(zip_names "$repo/dist/good-skill.zip")" \
      && grep -qx "packaged dist/good-skill.zip" <<<"$out"' \
    "$out"
}

# gets_no_zip <case> <reason>: validate.sh and package.sh must both say the
# good skill gets no zip, and package.sh must say why, in one line naming the
# skill, and exit 0.
gets_no_zip() {
  local reason="$2"
  commit_all
  pack
  check "no zip: $1" \
    '[ "$status" -eq 0 ] && [ "$(validate_says good-skill)" = "no zip" ] && [ -z "$(zips)" ] \
      && [ "$out" = "skipped good-skill: no zip, because $reason" ]' \
    "$out"
}

echo "Testing $package"
echo "with yq:    $(command -v yq): $(yq --version 2>&1 | head -n 1)"
echo "     jq:    $(command -v jq): $(jq --version 2>&1 | head -n 1)"
echo "     git:   $(command -v git): $(git --version 2>&1 | head -n 1)"
echo "     unzip: $(command -v unzip): $(unzip -v 2>&1 | head -n 1)"
echo "     bash:  $(command -v bash): $(bash --version | head -n 1)"
echo

# --- What goes in a zip -------------------------------------------------------

new_repo
gets_zip "a good skill"

new_repo
mkdir -p "$repo/skills/good-skill/references"
echo "More about the thing." > "$repo/skills/good-skill/references/more.md"
commit_all
echo "SECRET=not-committed" > "$repo/skills/good-skill/.env"
echo "A draft." > "$repo/skills/good-skill/references/draft.md"
pack
check "a file that is not committed stays out of the zip" \
  '[ "$status" -eq 0 ] && [ "$(zip_names "$repo/dist/good-skill.zip" | sort | tr "\n" " ")" = "good-skill/ good-skill/SKILL.md good-skill/references/ good-skill/references/more.md " ]' \
  "$(zip_names "$repo/dist/good-skill.zip" | tr '\n' ' ')"
cases=$((cases + 1))
check "and package.sh says the skill has changes that are not committed" \
  'grep -qx "note: skills/good-skill has changes that are not committed. They are left out: what is packaged is the last commit." <<<"$out"' \
  "$(grep '^note: ' <<<"$out")"

new_repo
commit_all
pack
check "a skill with nothing uncommitted gets no such line" '! grep -q "not committed" <<<"$out"' "$out"

new_repo
commit_all
echo "An edit that was not committed." >> "$repo/skills/good-skill/SKILL.md"
pack
check "an edit that is not committed stays out of the zip" \
  '[ "$status" -eq 0 ] && grep -q "^# Good skill" <<<"$(unzip -p "$repo/dist/good-skill.zip" good-skill/SKILL.md)" \
    && ! grep -q "An edit" <<<"$(unzip -p "$repo/dist/good-skill.zip" good-skill/SKILL.md)"' \
  "$(grep '^note: ' <<<"$out")"

# The decision is made about the committed SKILL.md, the one that goes in the
# zip, not the one in the working folder.
new_repo
commit_all
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
---
MD
pack
check "a key the apps reject, added but not committed, does not stop the zip of the commit" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = good-skill.zip ] && ! grep -q argument-hint <<<"$(unzip -p "$repo/dist/good-skill.zip" good-skill/SKILL.md)"' \
  "$out"

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
---
MD
commit_all
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
---
MD
pack
check "a key the apps reject, removed but not committed, still means no zip" \
  '[ "$status" -eq 0 ] && [ -z "$(zips)" ] && grep -qx "skipped good-skill: no zip, because the Claude apps reject these frontmatter keys: argument-hint" <<<"$out"' \
  "$out"

# A link that points outside the skill folder. The file it points to must not
# end up in the zip: the link is kept as a link.
new_repo
echo "TOKEN=outside-the-skill" > "$repo/private.txt"
ln -s ../../private.txt "$repo/skills/good-skill/notes.txt"
commit_all
pack
check "a link pointing outside the skill is not followed" \
  '[ "$status" -eq 0 ] && [ "$(unzip -p "$repo/dist/good-skill.zip" good-skill/notes.txt)" = "../../private.txt" ] \
    && ! grep -q "outside-the-skill" <<<"$(unzip -p "$repo/dist/good-skill.zip")" \
    && grep -qx "note: dist/good-skill.zip holds good-skill/notes.txt as a link, not as the file it points to." <<<"$out"' \
  "$(grep '^note: ' <<<"$out")"

new_repo
ln -s "$repo/.claude-plugin/marketplace.json" "$repo/skills/good-skill/absolute.json"
commit_all
pack
check "a link with a full path is not followed either" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = good-skill.zip ] && ! grep -q "example-skills" <<<"$(unzip -p "$repo/dist/good-skill.zip")"' \
  "$(grep '^note: ' <<<"$out")"

new_repo
echo "junk" > "$repo/skills/good-skill/.DS_Store"
mkdir "$repo/skills/good-skill/assets"
echo "junk" > "$repo/skills/good-skill/assets/.DS_Store"
echo "kept" > "$repo/skills/good-skill/assets/kept.txt"
commit_all
pack
check "a .DS_Store file stays out of the zip, even a committed one" \
  '[ "$status" -eq 0 ] && grep -qx "good-skill/assets/kept.txt" <<<"$(zip_names "$repo/dist/good-skill.zip")" \
    && ! grep -q "DS_Store" <<<"$(zip_names "$repo/dist/good-skill.zip")"' \
  "$(zip_names "$repo/dist/good-skill.zip" | tr '\n' ' ')"

new_repo
mkdir "$repo/dist" "$repo/docs"
echo "old" > "$repo/dist/old-skill.zip"
echo "keep me" > "$repo/docs/keep.txt"
echo "keep me" > "$repo/untracked.txt"
commit_all
echo "keep me too" > "$repo/skills/good-skill/untracked.txt"
pack
check "dist/ is emptied first, and nothing outside it is deleted" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = good-skill.zip ] && [ -f "$repo/docs/keep.txt" ] && [ -f "$repo/untracked.txt" ] \
    && [ -f "$repo/skills/good-skill/untracked.txt" ] && [ -z "$(case_git status --porcelain -- . ":(exclude)dist" ":(exclude)skills/good-skill/untracked.txt")" ]' \
  "dist/ holds: $(zips)"

# --- The same commit gives the same zip ---------------------------------------

new_repo
mkdir -p "$repo/skills/good-skill/scripts"
printf '#!/bin/sh\necho thing\n' > "$repo/skills/good-skill/scripts/run.sh"
chmod +x "$repo/skills/good-skill/scripts/run.sh"
long_description 4000 > "$repo/skills/good-skill/reference.txt"
commit_all
pack
first="$(checksum "$repo/dist/good-skill.zip")"
cp "$repo/dist/good-skill.zip" "$work/first.zip"
sleep 2
pack
check "packaging the same commit twice gives the same bytes" \
  '[ "$status" -eq 0 ] && cmp -s "$work/first.zip" "$repo/dist/good-skill.zip"' \
  "checksum and size of good-skill.zip (cksum): $first"

# The file times, the time zone and the permissions of the working folder must
# not reach the zip.
touch "$repo/skills/good-skill/SKILL.md" "$repo/skills/good-skill/scripts/run.sh"
chmod 600 "$repo/skills/good-skill/reference.txt"
cases=$((cases + 1))
out="$(umask 077 && TZ=Asia/Tokyo "$package" "$repo" 2>&1)"
status=$?
check "and again in another time zone, with other file times and permissions" \
  '[ "$status" -eq 0 ] && cmp -s "$work/first.zip" "$repo/dist/good-skill.zip"' \
  "$(checksum "$repo/dist/good-skill.zip")"

# Nor must the line-ending setting of whoever runs it.
cases=$((cases + 1))
case_git config core.autocrlf true
pack
check "and again with git set to convert line endings" \
  '[ "$status" -eq 0 ] && cmp -s "$work/first.zip" "$repo/dist/good-skill.zip"' \
  "$(checksum "$repo/dist/good-skill.zip")"

# A second checkout of the same commit.
cases=$((cases + 1))
original="$repo"
GIT_CONFIG_GLOBAL=/dev/null git clone -q "$original" "$work/second-checkout" > /dev/null 2>&1
repo="$work/second-checkout"
pack
check "and again from a second checkout of the same commit" \
  '[ "$status" -eq 0 ] && cmp -s "$work/first.zip" "$repo/dist/good-skill.zip" \
    && [ "$(case_git rev-parse HEAD)" = "$(git -C "$original" rev-parse HEAD)" ]' \
  "commit $(case_git rev-parse HEAD): $(checksum "$repo/dist/good-skill.zip")"

cases=$((cases + 1))
check "the zip keeps a script runnable and a text file not" \
  'grep -q "^-rwx.*good-skill/scripts/run.sh" <<<"$(unzip -Z "$repo/dist/good-skill.zip")" && grep -q "^-rw-.*good-skill/reference.txt" <<<"$(unzip -Z "$repo/dist/good-skill.zip")"' \
  "$(unzip -Z "$repo/dist/good-skill.zip" | grep 'good-skill/.*\.' | awk '{ print $1, $NF }' | tr '\n' ' ')"

# A different commit of the same files gives a different zip: the check above
# is not passing because every zip is the same.
new_repo
mkdir -p "$repo/skills/good-skill/scripts"
printf '#!/bin/sh\necho thing\n' > "$repo/skills/good-skill/scripts/run.sh"
chmod +x "$repo/skills/good-skill/scripts/run.sh"
long_description 4000 > "$repo/skills/good-skill/reference.txt"
echo "One more line." >> "$repo/skills/good-skill/SKILL.md"
commit_all
pack
check "a commit with a changed file gives a different zip" \
  '[ "$status" -eq 0 ] && ! cmp -s "$work/first.zip" "$repo/dist/good-skill.zip"' \
  "$(checksum "$repo/dist/good-skill.zip")"

# --- Which skills get a zip: the same answer as validate.sh --------------------

# These four have a key outside the six that looks like one of the six. The
# line-by-line check package.sh used to have made a zip for each.
shape_without_zip() { # shape_without_zip <case> <frontmatter line> <key>
  new_repo
  write_skill good-skill <<MD
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
$2
---
MD
  gets_no_zip "$1" "the Claude apps reject these frontmatter keys: $3"
}

shape_without_zip 'the key metadata:x' 'metadata:x: y' 'metadata:x'
shape_without_zip 'the key license:mit' 'license:mit: yes' 'license:mit'
shape_without_zip 'the key metadata"' 'metadata": y' 'metadata"'
shape_without_zip 'the quoted key "license: x"' '"license: x": y' 'license: x'

# These eight are valid and have no key outside the six. The old check skipped
# each of them.
shape_with_zip() { # shape_with_zip <case>, with the frontmatter on standard input
  new_repo
  {
    echo "---"
    cat
    echo "---"
    echo
    echo "# Good skill"
  } > "$repo/skills/good-skill/SKILL.md"
  gets_zip "$1"
}

shape_with_zip "a quoted value continued on a line with no indent" <<'MD'
name: good-skill
description: "Does a thing.
Use when the thing needs doing."
MD

shape_with_zip "a [a, b] list continued on a line with no indent" <<'MD'
name: good-skill
description: Does a thing. Use when the thing needs doing.
allowed-tools: [Read,
Grep]
MD

shape_with_zip "a list under a key with no indent" <<'MD'
name: good-skill
description: Does a thing. Use when the thing needs doing.
allowed-tools:
- Read
- Grep
MD

shape_with_zip "all keys on one line in braces" <<'MD'
{name: good-skill, description: Does a thing. Use when the thing needs doing.}
MD

shape_with_zip "a key written with a question mark" <<'MD'
? name
: good-skill
description: Does a thing. Use when the thing needs doing.
MD

shape_with_zip "a key with a tag" <<'MD'
!!str name: good-skill
description: Does a thing. Use when the thing needs doing.
MD

shape_with_zip "a quoted key with an escape in it" <<'MD'
"na\x6de": good-skill
description: Does a thing. Use when the thing needs doing.
MD

shape_with_zip "every key indented by the same amount" <<'MD'
  name: good-skill
  description: Does a thing. Use when the thing needs doing.
  license: MIT
MD

# Ordinary shapes, and the keys of this repository's own skill.
shape_with_zip "all six keys" <<'MD'
name: good-skill
description: >
  Does a thing.
  Use when the thing needs doing.
license: MIT
compatibility: Needs nothing.
metadata:
  author: example
  argument-hint: nested, so not a top-level key
allowed-tools: Read Grep
MD

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
disable-model-invocation: true
---
MD
gets_no_zip "keys only Claude Code reads" "the Claude apps reject these frontmatter keys: argument-hint, disable-model-invocation"

# --- A skill that fails validation --------------------------------------------

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: ""
---
MD
gets_no_zip "a skill with an empty description" "validate.sh found a problem in it: skills/good-skill/SKILL.md: description is empty"

new_repo
write_skill good-skill <<'MD'
---
name: another-name
description: ""
extra: 1
---
MD
gets_no_zip "a skill with two problems" 'validate.sh found 2 problems in it: skills/good-skill/SKILL.md: name "another-name" does not match its folder name "good-skill"; skills/good-skill/SKILL.md: description is empty'

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
name: good-skill
description: Does a thing. Use when the thing needs doing.
---
MD
gets_no_zip "a skill with the same key twice" 'validate.sh found a problem in it: skills/good-skill/SKILL.md: the frontmatter has "name" more than once'

new_repo
printf '# No frontmatter here\n' > "$repo/skills/good-skill/SKILL.md"
gets_no_zip "a skill with no frontmatter" "validate.sh found a problem in it: skills/good-skill/SKILL.md has no frontmatter: its first line must be ---"

# One skill failing does not stop the others from being packaged.
new_repo
write_skill bad-skill <<'MD'
---
name: bad-skill
---
MD
write_skill claude-code-only <<'MD'
---
name: claude-code-only
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
---
MD
commit_all
pack
check "a failing skill and a Claude Code-only skill are skipped, and the good one is packaged" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = good-skill.zip ] && [ "$(grep -c . <<<"$out")" -eq 3 ] \
    && grep -qx "skipped bad-skill: no zip, because validate.sh found a problem in it: skills/bad-skill/SKILL.md has no description in its frontmatter" <<<"$out" \
    && grep -qx "skipped claude-code-only: no zip, because the Claude apps reject these frontmatter keys: argument-hint" <<<"$out" \
    && grep -qx "packaged dist/good-skill.zip" <<<"$out"' \
  "$out"

# A skill folder that is not listed in the manifest is a fault in the manifest,
# not in the skill, so it does not change which skills get a zip.
new_repo
write_skill second-skill <<'MD'
---
name: second-skill
description: Does another thing. Use when it needs doing.
---
MD
commit_all
pack
check "two good skills get a zip each" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = "good-skill.zip second-skill.zip" ] \
    && grep -qx "second-skill/SKILL.md" <<<"$(zip_names "$repo/dist/second-skill.zip")" \
    && ! grep -q "good-skill" <<<"$(zip_names "$repo/dist/second-skill.zip")"' \
  "$out"

# --- Every skill skipped, and no skills ---------------------------------------

new_repo
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
argument-hint: "[thing]"
---
MD
write_skill bad-skill <<'MD'
---
name: bad-skill
description: ""
---
MD
mkdir "$repo/dist"
echo "old" > "$repo/dist/old-skill.zip"
commit_all
pack
check "every skill skipped: exit 0 and no zips" \
  '[ "$status" -eq 0 ] && [ -d "$repo/dist" ] && [ -z "$(zips)" ] && [ "$(grep -c "^skipped " <<<"$out")" -eq 2 ] && [ "$(grep -c . <<<"$out")" -eq 2 ]' \
  "$out"

new_repo
rm -r "$repo/skills"
commit_all
pack
check "no skills at all: exit 1" \
  '[ "$status" -eq 1 ] && [ "$out" = "no skills found under skills/ in the last commit" ] && [ -z "$(zips)" ]' \
  "$out"

new_repo
rm "$repo/skills/good-skill/SKILL.md"
echo "Not a skill." > "$repo/skills/good-skill/README.md"
commit_all
pack
check "only a folder with no SKILL.md: skipped with the reason, and exit 1" \
  '[ "$status" -eq 1 ] && [ -z "$(zips)" ] && grep -qx "skipped good-skill: no zip, because validate.sh found a problem in it: skills/good-skill has no SKILL.md" <<<"$out" \
    && grep -qx "no skills found under skills/ in the last commit" <<<"$out"' \
  "$out"

# A skill that has not been committed yet is not in the last commit.
new_repo
rm -r "$repo/skills"
commit_all
write_skill good-skill <<'MD'
---
name: good-skill
description: Does a thing. Use when the thing needs doing.
---
MD
pack
check "only a skill that is not committed: it is named, and exit 1" \
  '[ "$status" -eq 1 ] && [ -z "$(zips)" ] && grep -qx "skipped good-skill: no zip, because none of it is committed. Only committed files are packaged." <<<"$out"' \
  "$out"

new_repo
commit_all
write_skill new-skill <<'MD'
---
name: new-skill
description: Does a new thing. Use when it needs doing.
---
MD
pack
check "a skill that is not committed, beside one that is" \
  '[ "$status" -eq 0 ] && [ "$(zips)" = good-skill.zip ] && grep -qx "skipped new-skill: no zip, because none of it is committed. Only committed files are packaged." <<<"$out"' \
  "$out"

# --- Not a git checkout -------------------------------------------------------

# stops <case> <text>: package.sh must exit 2 with a message containing the
# text, in lines that start "error: " or carry one on, and leave dist/ alone.
stops() {
  local text="$2"
  mkdir -p "$repo/dist"
  echo "old" > "$repo/dist/old-skill.zip"
  pack
  check "stops: $1" \
    '[ "$status" -eq 2 ] && grep -qF -- "$text" <<<"$out" && ! grep -qvE "^(error: |       )" <<<"$out" && [ "$(zips)" = old-skill.zip ]' \
    "$out"
}

# A downloaded source archive: the files, with no .git folder.
new_repo
stops "a folder that is not a git checkout" "is not in a git checkout."
cases=$((cases + 1))
check "and it says what to do" 'grep -qF "A downloaded source archive has no commits to package." <<<"$out"' "(it does)"

# The same, unpacked inside some other git checkout: that checkout's commits
# are not this repository's.
new_repo
outer="$repo"
commit_all
repo="$outer/unpacked"
mkdir -p "$repo/.claude-plugin"
cp "$outer/.claude-plugin/marketplace.json" "$repo/.claude-plugin/"
write_skill good-skill < "$outer/skills/good-skill/SKILL.md"
stops "a folder inside another git checkout" "is a folder inside another git checkout"

new_repo
case_git init -q . > /dev/null 2>&1
stops "a git checkout with no commits" "has no commits yet."

# --- yq or jq missing, or the wrong yq ----------------------------------------

# Run package.sh with a PATH that holds only the tools named, as links.
tool_case() { # tool_case <case> <text> <tool>...
  local name="$1" text="$2" bin tool
  shift 2
  new_repo
  commit_all
  mkdir -p "$repo/dist"
  echo "old" > "$repo/dist/old-skill.zip"
  bin="$work/bin-$cases"
  mkdir "$bin"
  for tool in dirname "$@"; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done
  out="$(PATH="$bin" "$BASH" "$package" "$repo" 2>&1)"
  status=$?
  check "stops: $name" \
    '[ "$status" -eq 2 ] && grep -qF -- "$text" <<<"$out" && grep -qF "brew install yq jq" <<<"$out" \
      && ! grep -qvE "^(error: |       )" <<<"$out" && [ "$(zips)" = old-skill.zip ]' \
    "$out"
}

tool_case "no yq on the PATH" 'error: package.sh needs yq, and there is no yq on the PATH.' jq git
tool_case "no jq on the PATH" 'error: package.sh needs jq, and there is no jq on the PATH.' yq git

# The other tool called yq, the Python one, first on the PATH. validate.sh is
# the one that notices, and package.sh passes on what it says.
new_repo
commit_all
mkdir "$work/other-yq"
printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$work/other-yq/yq"
chmod +x "$work/other-yq/yq"
out="$(PATH="$work/other-yq:$PATH" "$package" "$repo" 2>&1)"
status=$?
check "stops: the other yq (the Python one)" \
  '[ "$status" -eq 2 ] && grep -qF "This one says: yq 3.4.3" <<<"$out" && ! grep -qvE "^(error: |       )" <<<"$out" && [ -z "$(zips)" ]' \
  "$out"

new_repo
commit_all
out="$("$package" "$repo" extra 2>&1)"
status=$?
check "stops: more than one folder given" '[ "$status" -eq 2 ] && grep -q "^usage: " <<<"$out"' "$out"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures of $cases cases FAILED"
  exit 1
fi
echo "all $cases cases behaved as expected"
