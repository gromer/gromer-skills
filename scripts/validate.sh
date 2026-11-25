#!/usr/bin/env bash
# Check that the Claude marketplace manifest has the fields it needs, that
# every folder under skills/ is a well-formed skill, and that the manifest and
# the folders list the same skills.
#
# Usage: scripts/validate.sh [repository]
#        scripts/validate.sh --skill <folder> [repository]
#
# With no argument it checks the repository this script is in. Give a folder to
# check that one instead, which is how scripts/test-validate.sh runs it against
# broken examples.
#
# With --skill it checks only skills/<folder>, and not the manifest: it prints
# that skill's "error: ..." lines and its "note: ..." line, if it has any, and
# exits 1 if there was an error. scripts/package.sh asks this for each skill,
# so that a skill gets an upload zip exactly when this script finds no error in
# it and prints no note for it.
#
# Needs yq and jq. SKILL.md frontmatter is YAML, so yq reads it and turns it
# into JSON, and jq does the checking; jq also reads the manifest. The GitHub
# Actions ubuntu-latest runner has both. On macOS: brew install yq jq
#
# yq here is the Go one, version 4 or later (https://github.com/mikefarah/yq).
# There is another tool called yq, a Python wrapper around jq, which takes
# different options and won't work.
#
# Written for macOS's own /bin/bash (3.2) as well as newer ones.
set -euo pipefail
export LC_ALL=C

only_skill=""
if [ "${1:-}" = "--skill" ] && [ "$#" -ge 2 ] && [ -n "$2" ]; then
  only_skill="$2"
  shift 2
fi

if [ "$#" -gt 1 ] || [ "${1:-}" = "--skill" ]; then
  echo "usage: $0 [repository]" >&2
  echo "       $0 --skill <folder> [repository]" >&2
  exit 2
fi

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# A folder whose name starts with a dash would be taken for an option by the
# tools below.
case "$root" in
  -*) root="./$root" ;;
esac

if [ ! -d "$root" ]; then
  echo "error: $root is not a folder" >&2
  exit 2
fi

# --- The tools this script needs ---------------------------------------------

missing=0
for tool in yq jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: validate.sh needs $tool, and there is no $tool on the PATH." >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "       On macOS, install both with: brew install yq jq" >&2
  exit 2
fi

yq_version=""
IFS= read -r yq_version < <(yq --version 2>&1) || true
case "$yq_version" in
  *mikefarah*version\ v[4-9]* | *mikefarah*version\ [4-9]*) ;;
  *)
    echo "error: the yq on the PATH ($(command -v yq)) is not the one validate.sh needs." >&2
    echo "       It needs the Go yq, version 4 or later (https://github.com/mikefarah/yq)." >&2
    echo "       On macOS, install it with: brew install yq" >&2
    echo "       This one says: ${yq_version:-nothing, when asked for its version}" >&2
    exit 2
    ;;
esac

# --- Setup --------------------------------------------------------------------

manifest=".claude-plugin/marketplace.json"

# The Claude apps reject an uploaded skill whose frontmatter has any top-level
# key outside these six, so scripts/package.sh makes no upload zip for one.
uploadable_keys='["name", "description", "license", "compatibility", "metadata", "allowed-tools"]'

# Limits from the Agent Skills specification (agentskills.io/specification).
max_name=64
max_description=1024

tmp="$(mktemp -d "${TMPDIR:-/tmp}/validate.XXXXXX" 2> /dev/null)" || {
  echo "error: validate.sh could not make a temporary folder in ${TMPDIR:-/tmp}" >&2
  exit 2
}
trap 'rm -rf "$tmp"' EXIT

errors=0
err() {
  echo "error: $*" >&2
  errors=$((errors + 1))
}

# True for a file that is UTF-8 text. jq puts a stand-in character where it
# meets a byte that is not UTF-8, without saying so, which would let a file
# saved in another encoding through. Where there is no iconv to ask, the file
# is taken to be fine.
is_utf8() {
  ! command -v iconv > /dev/null 2>&1 || iconv -f UTF-8 -t UTF-8 "$1" > /dev/null 2>&1
}

# True for a file that is there and can be opened. A link to a file that is
# not there, a file with no read permission and a folder are all not.
is_readable() {
  [ -f "$1" ] && [ -r "$1" ]
}

# True for a file that is strictly JSON. jq reads more than JSON: it takes 007,
# .5, +1, 1., NaN and Infinity as numbers, which Claude Code does not. yq reads
# JSON strictly. It also refuses a byte-order mark at the start of the file,
# which Claude Code accepts, so that is taken off first. What yq said is left
# in the file yq-error.
is_strict_json() {
  awk 'NR == 1 && substr($0, 1, 3) == "\357\273\277" { $0 = substr($0, 4) } { print }' "$1" > "$tmp/strict.json"
  yq eval --input-format=json --output-format=json '.' "$tmp/strict.json" > /dev/null 2> "$tmp/yq-error"
}

# Print the lines a jq program gave: "error: ..." lines count as errors, and
# "note: ..." lines are passed on.
report() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "error: "*) err "${line#error: }" ;;
      "note: "*) echo "$line" ;;
    esac
  done
}

# --- The marketplace manifest -------------------------------------------------

# A jq program that prints one "error: ..." line for each problem in the
# manifest. It is given the file's JSON values as one list.
manifest_checks() {
  cat <<'JQ'
# A value's type, in plain words.
def kind:
  if type == "string" then "text"
  elif type == "number" then "a number (\(.))"
  elif type == "boolean" then "\(.)"
  elif type == "null" then "null"
  elif type == "array" then "a list"
  else "an object" end;

# True for text that is empty or only spaces and line breaks.
def blank: explode | all(. == 32 or . == 9 or . == 10 or . == 13);

# A field that is missing, not text, or empty. $where says which object the
# field is in.
def text_problem($key; $where):
  if has($key) | not then "\($where) has no \"\($key)\""
  elif (.[$key] | type) != "string" then "\($where): \"\($key)\" must be text, but it is \(.[$key] | kind)"
  elif (.[$key] | blank) then "\($where): \"\($key)\" is empty"
  else empty end;

# A plugin's "source" is either a path inside this repository, as text, or an
# object that says where to fetch the plugin from. The object names its kind in
# a "source" key of its own, for example { "source": "github", "repo": "..." }.
def source_problem($where):
  if has("source") | not then "\($where) has no \"source\""
  else
    .source as $source
    | if ($source | type) == "string" then
        (if ($source | blank) then "\($where): \"source\" is empty" else empty end)
      elif ($source | type) == "object" then
        (if ($source.source | type) == "string" and ($source.source | blank | not) then empty
         else "\($where): its \"source\" object must name its kind in a \"source\" key of its own, for example \"github\"" end)
      else
        "\($where): \"source\" must be a path such as \"./\", or an object saying where to fetch the plugin from, but it is \($source | kind)"
      end
  end;

def skills_problem($where):
  if has("skills") | not then empty
  elif (.skills | type) == "string" then empty
  elif (.skills | type) == "array" and (.skills | all(type == "string")) then empty
  else "\($where): \"skills\" must be a list of paths such as \"./skills/my-skill\"" end;

def plugin_problems($where):
  if type != "object" then "\($where) must be an object, but it is \(kind)"
  else
    (if (.name | type) == "string" and (.name | blank | not) then "\($where) (\"\(.name)\")" else $where end) as $named
    | text_problem("name"; $named), source_problem($named), skills_problem($named)
  end;

def manifest_problems:
  if type != "object" then "\($manifest) must be a JSON object, but it is \(kind)"
  else
    text_problem("name"; $manifest),
    (if has("owner") | not then "\($manifest) has no \"owner\""
     elif (.owner | type) != "object" then "\($manifest): \"owner\" must be an object with a \"name\", but it is \(.owner | kind)"
     else .owner | text_problem("name"; "\($manifest): \"owner\"") end),
    (if has("plugins") | not then "\($manifest) has no \"plugins\" list"
     elif (.plugins | type) != "array" then "\($manifest): \"plugins\" must be a list, but it is \(.plugins | kind)"
     else .plugins | to_entries[] | .key as $index | .value | plugin_problems("\($manifest): plugin \($index + 1)") end)
  end;

if length != 1 then "\($manifest) must hold one JSON object"
else .[0] | manifest_problems end
| "error: " + (split("\n") | join(" "))
JQ
}

# A jq program that prints the skill folders the manifest lists, such as
# ./skills/issue-flow, one to a line.
listed_skills() {
  cat <<'JQ'
.[0].plugins[] | objects | .skills
| if type == "string" then . elif type == "array" then .[] | strings else empty end
JQ
}

# The manifest's list of skills is only compared with the folders when the
# manifest could be read well enough to have one.
listed_known=0
: > "$tmp/listed"

if [ -n "$only_skill" ]; then
  : # One skill was asked for, so the manifest is not looked at.
elif [ ! -e "$root/$manifest" ] && [ ! -L "$root/$manifest" ]; then
  err "$manifest was not found"
elif ! is_readable "$root/$manifest"; then
  err "$manifest could not be read"
elif ! is_utf8 "$root/$manifest"; then
  err "$manifest is not UTF-8 text"
elif ! jq -s . "$root/$manifest" > /dev/null 2> "$tmp/jq-error"; then
  err "$manifest is not valid JSON ($(sed -e 's/^jq: error (at [^)]*): //' -e 's/^jq: //' -e 1q "$tmp/jq-error" | cut -c 1-120))"
elif ! is_strict_json "$root/$manifest"; then
  err "$manifest is not valid JSON ($(sed -e 's/^Error: //' -e "s/^bad file '[^']*': //" -e 1q "$tmp/yq-error" | cut -c 1-120))"
elif ! jq -r -s --arg manifest "$manifest" "$(manifest_checks)" "$root/$manifest" > "$tmp/manifest-problems" 2> "$tmp/jq-error"; then
  # Not expected: the checks themselves stopped. Say so in one line.
  err "$manifest could not be checked ($(sed -e 1q "$tmp/jq-error" | cut -c 1-160))"
else
  report < "$tmp/manifest-problems"
  if jq -e -s 'length == 1 and (.[0] | type) == "object"' "$root/$manifest" > /dev/null \
    && jq -e -s '(.[0].plugins | type) == "array"' "$root/$manifest" > /dev/null; then
    listed_known=1
    jq -r -s "$(listed_skills)" "$root/$manifest" | sed -e 's|^\./||' -e 's|/*$||' | sort -u > "$tmp/listed"
  fi
fi

# --- SKILL.md frontmatter -----------------------------------------------------

# A jq program that prints an "error: ..." line for each problem in a skill's
# frontmatter, and a "note: ..." line if the skill gets no upload zip. It is
# given the frontmatter as JSON.
skill_checks() {
  cat <<'JQ'
def space: . == 32 or . == 9 or . == 10 or . == 13;

# True for text that is empty or only spaces and line breaks.
def blank: explode | all(space);

# The number of characters, not counting spaces and line breaks at either end.
def trimmed_length:
  explode
  | until(length == 0 or (.[0] | space | not); .[1:])
  | until(length == 0 or (.[-1] | space | not); .[:-1])
  | length;

# The value as text. An empty value is "". A list or nested keys is null.
def as_text:
  if type == "string" then .
  elif type == "number" or type == "boolean" then tostring
  elif type == "null" then ""
  else null end;

# What is wrong with a skill name under the Agent Skills naming rules, as a
# list of reasons. The rules allow lowercase a-z, digits and hyphens.
def name_problems:
  [ (if length > $max_name then "it is \(length) characters and the limit is \($max_name)" else empty end),
    (if explode | all((. >= 97 and . <= 122) or (. >= 48 and . <= 57) or . == 45) then empty
     else "it may only contain lowercase letters (a-z), digits and hyphens" end),
    (if startswith("-") or endswith("-") then "it must not start or end with a hyphen" else empty end),
    (if index("--") != null then "it must not have two hyphens in a row" else empty end) ];

# YAML reads a value written without quotes as a number, as true or false, or
# as no value, when it looks like one: 007 is the number 7, and null is no
# value. This says which of those a value was read as; text gives nothing.
def read_as:
  if type == "number" then "a number"
  elif type == "boolean" then "true or false"
  elif type == "null" then "no value"
  else empty end;

def name_lines:
  if has("name") | not then "error: \($file) has no name in its frontmatter"
  else
    (.name | as_text) as $name
    | if $name == null then "error: \($file): name must be text, not a list or nested keys"
      elif (.name | type) != "string" and $name != $folder and ($name != "" or $folder == "null") then
        # The name as YAML read it is not the name as written, so say that and
        # not what YAML made of it. A number that still reads the same, such as
        # 2048, goes on to the checks below.
        "error: \($file): name is read by YAML as \(.name | read_as), not as text, so it does not match its folder name \"\($folder)\". If the name is right, put it in quotes: name: \"\($folder)\""
      elif ($name | blank) then "error: \($file): name is empty"
      else
        (if $name != $folder then "error: \($file): name \"\($name)\" does not match its folder name \"\($folder)\"" else empty end),
        ($name | name_problems
         | if length > 0 then "error: \($file): name \"\($name)\" breaks the Agent Skills naming rules: \(join("; "))" else empty end)
      end
  end;

def description_lines:
  if has("description") | not then "error: \($file) has no description in its frontmatter"
  else
    (.description | as_text) as $description
    | if $description == null then "error: \($file): description must be text, not a list or nested keys"
      elif ($description | blank) then "error: \($file): description is empty"
      elif ($description | trimmed_length) > $max_description then
        "error: \($file): description is \($description | trimmed_length) characters and the limit is \($max_description)"
      else empty end
  end;

def note_lines:
  (keys_unsorted - $uploadable)
  | if length > 0 then
      "note: skills/\($folder) gets no upload zip, because the Claude apps reject these frontmatter keys: \(join(", "))"
    else empty end;

if type == "null" then "error: \($file): the frontmatter is empty"
elif type != "object" then "error: \($file): the frontmatter must be 'key: value' lines, such as 'name: my-skill'"
else name_lines, description_lines, note_lines end
| split("\n") | join(" ")
JQ
}

check_skill() {
  local folder="$1"
  local file="skills/$folder/SKILL.md"
  local status=0 json problem repeated

  if ! is_readable "$root/$file"; then
    err "$file could not be read. It may be a link to a file that is not there, a folder, or a file with no read permission"
    return
  fi
  if ! is_utf8 "$root/$file"; then
    err "$file is not UTF-8 text"
    return
  fi

  # The frontmatter is the block between the first two '---' lines. The opening
  # line is kept, so that yq's line numbers are the file's line numbers.
  awk '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    NR == 1 && substr(line, 1, 3) == "\357\273\277" { code = 5; exit }
    NR == 1 { if (line != "---") { code = 3; exit }; print "---"; next }
    line == "---" { closed = 1; exit }
    { sub(/\r$/, ""); print }
    END { if (NR == 0) code = 3; else if (!code && !closed) code = 4; exit code }
  ' "$root/$file" > "$tmp/frontmatter" || status=$?
  case "$status" in
    0) ;;
    3)
      err "$file has no frontmatter: its first line must be ---"
      return
      ;;
    4)
      err "$file: the frontmatter is never closed. It opens with --- on line 1, but no later line is ---"
      return
      ;;
    5)
      err "$file starts with a byte-order mark, an invisible character some editors add, so its frontmatter is not found. Save the file without it"
      return
      ;;
    *)
      err "$file could not be read"
      return
      ;;
  esac

  if ! json="$(yq eval --output-format=json '.' "$tmp/frontmatter" 2> "$tmp/yq-error")"; then
    # Keep the first line of what yq said, without its own prefixes. Depending
    # on its version, yq gives the place as "line 3:", or as "L3.C28:" or
    # "L3.C14-L4.C1:" after a clause in brackets.
    problem="$(sed -E -e 's/^Error: //' -e "s/^bad file '[^']*': //" -e 's/^yaml: //' \
      -e 's/^go-yaml load error in [a-z]+ (\([^)]*\) )?at L([0-9]+)\.C[0-9]+(-(L[0-9]+\.)?C[0-9]+)?: /line \2: /' \
      -e 1q "$tmp/yq-error" | cut -c 1-160)"
    err "$file: the frontmatter is not valid YAML (${problem:-yq could not read it})"
    return
  fi
  [ -n "$json" ] || json=null

  if ! printf '%s\n' "$json" | jq -r \
    --arg file "$file" --arg folder "$folder" \
    --argjson uploadable "$uploadable_keys" \
    --argjson max_name "$max_name" --argjson max_description "$max_description" \
    "$(skill_checks)" > "$tmp/skill-problems" 2> "$tmp/jq-error"; then
    # Not expected: the checks themselves stopped. Say so in one line.
    err "$file could not be checked ($(sed -e 1q "$tmp/jq-error" | cut -c 1-160))"
    return
  fi
  report < "$tmp/skill-problems"

  # JSON keeps only the last of two keys with the same name, so ask yq.
  repeated="$(yq eval 'keys | .[]' "$tmp/frontmatter" 2> /dev/null | sort | uniq -d | head -n 1 || true)"
  if [ -n "$repeated" ]; then
    err "$file: the frontmatter has \"$repeated\" more than once"
  fi
}

# --- Run the checks -----------------------------------------------------------

: > "$tmp/on-disk"
: > "$tmp/no-skill-md"

# Check one folder under skills/.
check_folder() {
  local folder="$1"
  local dir="$root/skills/$folder/"
  # Look the file up by its exact name: macOS would otherwise accept skill.md,
  # which Linux does not.
  if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    echo "skills/$folder" >> "$tmp/no-skill-md"
    err "skills/$folder could not be read: it has no read permission"
  elif [ -n "$(find "$dir" -maxdepth 1 -name SKILL.md 2> /dev/null)" ]; then
    echo "skills/$folder" >> "$tmp/on-disk"
    check_skill "$folder"
  else
    echo "skills/$folder" >> "$tmp/no-skill-md"
    err "skills/$folder has no SKILL.md"
  fi
}

if [ -n "$only_skill" ]; then
  case "$only_skill" in
    */* | . | ..)
      echo "error: --skill takes the name of a folder under skills/, not a path: $only_skill" >&2
      exit 2
      ;;
  esac
  if [ ! -d "$root/skills/$only_skill" ]; then
    echo "error: skills/$only_skill is not a folder in $root" >&2
    exit 2
  fi
  check_folder "$only_skill"
  [ "$errors" -eq 0 ] || exit 1
  exit 0
fi

for dir in "$root"/skills/*/; do
  [ -d "$dir" ] || continue
  check_folder "$(basename "$dir")"
done

if [ ! -s "$tmp/on-disk" ] && [ ! -s "$tmp/no-skill-md" ]; then
  err "no skills found under skills/"
fi

if [ "$listed_known" -eq 1 ]; then
  sort -u -o "$tmp/on-disk" "$tmp/on-disk"
  sort -u -o "$tmp/no-skill-md" "$tmp/no-skill-md"
  while IFS= read -r skill; do
    err "$skill is not listed in $manifest"
  done < <(comm -23 "$tmp/on-disk" "$tmp/listed")
  # A listed folder that is there but has no SKILL.md was reported above.
  while IFS= read -r skill; do
    err "$manifest lists $skill, which has no SKILL.md"
  done < <(comm -13 "$tmp/on-disk" "$tmp/listed" | comm -23 - "$tmp/no-skill-md")
fi

if [ "$errors" -gt 0 ]; then
  echo "validation failed: $errors problem(s)" >&2
  exit 1
fi
echo "ok: $(wc -l < "$tmp/on-disk" | tr -d ' ') skill(s), manifest in sync"
