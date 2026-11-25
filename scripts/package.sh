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

# Print the top-level frontmatter keys of a SKILL.md that are not uploadable,
# one per line. The frontmatter is the block between the first two '---' lines.
# Indented lines (nested keys such as those under 'metadata:', and continued
# multi-line values) are not top-level keys, so they are not looked at.
other_keys() {
  awk -v allowed="$uploadable_keys" '
    BEGIN { n = split(allowed, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^[ \t]/ || /^#/ || $0 == "" { next }
    {
      key = $0
      sub(/[ \t]*:.*$/, "", key)
      gsub(/^["\047]|["\047]$/, "", key)
      if (!(key in ok)) print key
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

  other="$(other_keys "$skill_md" | paste -sd ',' - | sed 's/,/, /g')"
  if [ -n "$other" ]; then
    echo "skipped $name: no zip, because the Claude apps reject these frontmatter keys: $other"
    continue
  fi

  (cd "$root/skills" && zip -qr "$dist/$name.zip" "$name" -x '*.DS_Store')
  echo "packaged dist/$name.zip"
done

if [ "$found" -eq 0 ]; then
  echo "no skills found under skills/" >&2
  exit 1
fi
