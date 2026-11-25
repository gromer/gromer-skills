#!/usr/bin/env bash
# Zip each skill into dist/<name>.zip for uploading to the Claude or ChatGPT apps.
# The skill folder is the top level of each archive (<name>/SKILL.md), which is
# the shape the apps expect.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"

rm -rf "$dist"
mkdir -p "$dist"

count=0
for skill_md in "$root"/skills/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  name="$(basename "$(dirname "$skill_md")")"
  (cd "$root/skills" && zip -qr "$dist/$name.zip" "$name" -x '*.DS_Store')
  echo "packaged dist/$name.zip"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "no skills found under skills/" >&2
  exit 1
fi
