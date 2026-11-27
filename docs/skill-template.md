# Skill template

Copy the block below into `skills/<skill-name>/SKILL.md`. The folder name and the
`name` field must be the same: lowercase letters, numbers and hyphens.

```markdown
---
name: skill-name
description: What this skill does and when to use it. Lead with the main use case and the words someone would use when asking for it, because tools decide whether to load the skill from this line alone.
license: MIT
---

# Skill name

What the agent is doing and for whom, in a sentence or two.

## Steps

1. First step.
2. Second step.

## Output

What the result should look like.
```

`name` and `description` are required, and they are the only fields every tool
understands. Two optional fields from the Agent Skills format are worth
knowing:

- `license`: the license the skill is under. The block above has this
  repository's license, MIT. Keep the field, because installs and upload zips
  carry only the skill's folder, so the repository's `LICENSE` file doesn't
  travel with the skill. `gh skill publish` warns when it is missing.
- `compatibility`: what the skill needs in order to work, in 500 characters or
  fewer. Add it only when the skill needs a specific tool or setup, for example
  `compatibility: Works in the Claude, ChatGPT and GitHub Copilot desktop apps, because it needs an app's session tools. It doesn't work in their command-line tools.`

Add any other field only when a tool needs it. The Claude apps reject an
uploaded skill whose frontmatter has any key other than `name`, `description`,
`license`, `compatibility`, `metadata` and `allowed-tools`. For a skill with
any other key, `./scripts/package.sh` skips the skill, and releases have no zip
for it.

Supporting files go next to `SKILL.md`, in `scripts/`, `references/` or
`assets/`, and are referred to by relative path from the skill.

Then list the skill in `.claude-plugin/marketplace.json` and run
`./scripts/validate.sh`. See the README for the full steps.
