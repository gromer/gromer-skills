#!/usr/bin/env bash
# Zip each skill that the Claude apps will accept into dist/<name>.zip, for
# uploading under Customize > Skills. The skill folder is the top level of each
# archive (<name>/SKILL.md), which is the shape the apps expect.
#
# The apps reject an uploaded skill whose frontmatter has any top-level key
# outside the six below, so such a skill gets no zip. It is skipped with a line
# saying why, and that is not an error.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"

uploadable_keys="name description license compatibility metadata allowed-tools"

# Print why a SKILL.md can't be uploaded, or nothing if it can. The frontmatter
# is the block between the first two '---' lines. Indented lines (nested keys
# such as those under 'metadata:', and continued multi-line values) are not
# top-level keys, so they are not looked at. A skill gets a zip only when the
# frontmatter was found and has a top-level 'name', so that a file this check
# can't read (no frontmatter, or all of it indented) is skipped, not packaged
# unchecked.
skip_reason() {
  awk -v allowed="$uploadable_keys" '
    BEGIN { n = split(allowed, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    { sub(/[ \t\r]+$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { closed = 1; exit }
    /^[ \t]/ || /^#/ || $0 == "" { next }
    {
      key = $0
      sub(/[ \t]*:.*$/, "", key)
      gsub(/^["\047]|["\047]$/, "", key)
      if (key == "name") has_name = 1
      if (!(key in ok)) other = other (other == "" ? "" : ", ") key
    }
    END {
      if (!closed) print "its frontmatter was not found between two --- lines at the top of SKILL.md"
      else if (!has_name) print "no top-level name was found in its frontmatter"
      else if (other != "") print "the Claude apps reject these frontmatter keys: " other
    }
  ' "$1"
}

rm -rf "$dist"
mkdir -p "$dist"

found=0
for skill_md in "$root"/skills/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  found=$((found + 1))
  name="$(basename "$(dirname "$skill_md")")"

  reason="$(skip_reason "$skill_md")"
  if [ -n "$reason" ]; then
    echo "skipped $name: no zip, because $reason"
    continue
  fi

  (cd "$root/skills" && zip -qr "$dist/$name.zip" "$name" -x '*.DS_Store')
  echo "packaged dist/$name.zip"
done

if [ "$found" -eq 0 ]; then
  echo "no skills found under skills/" >&2
  exit 1
fi
