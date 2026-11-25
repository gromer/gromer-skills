#!/usr/bin/env bash
# Check that every skill folder is well formed and listed in the Claude
# marketplace manifest, and that the manifest lists nothing that is missing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/.claude-plugin/marketplace.json"
fail=0

err() {
  echo "error: $*" >&2
  fail=1
}

jq empty "$manifest" || { echo "error: $manifest is not valid JSON" >&2; exit 1; }

listed="$(jq -r '.plugins[].skills[]?' "$manifest" | sed 's|^\./||' | sort -u)"

on_disk=""
for skill_md in "$root"/skills/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  dir="$(basename "$(dirname "$skill_md")")"
  on_disk="$on_disk"$'\n'"skills/$dir"

  # The frontmatter is the block between the first two '---' lines.
  frontmatter="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$skill_md")"
  name="$(printf '%s\n' "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  description="$(printf '%s\n' "$frontmatter" | sed -n 's/^description:[[:space:]]*//p' | head -1)"

  [ -n "$name" ] || err "skills/$dir/SKILL.md has no 'name' in its frontmatter"
  [ -n "$description" ] || err "skills/$dir/SKILL.md has no 'description' in its frontmatter"
  [ -z "$name" ] || [ "$name" = "$dir" ] || err "skills/$dir: name '$name' does not match the folder name"
done
on_disk="$(printf '%s\n' "$on_disk" | sed '/^$/d' | sort -u)"

[ -n "$on_disk" ] || err "no skills found under skills/"

missing="$(comm -23 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$listed"))"
extra="$(comm -13 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$listed"))"

for s in $missing; do err "$s is not listed in .claude-plugin/marketplace.json"; done
for s in $extra; do err "marketplace.json lists $s, which has no SKILL.md"; done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok: $(printf '%s\n' "$on_disk" | wc -l | tr -d ' ') skill(s), manifest in sync"
