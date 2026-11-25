# Skill template

Copy the block below into `skills/<skill-name>/SKILL.md`. The folder name and the
`name` field must be the same: lowercase letters, numbers and hyphens.

```markdown
---
name: skill-name
description: What this skill does and when to use it. Lead with the main use case and the words someone would use when asking for it, because tools decide whether to load the skill from this line alone.
---

# Skill name

What the agent is doing and for whom, in a sentence or two.

## Steps

1. First step.
2. Second step.

## Output

What the result should look like.
```

Keep `name` and `description` as the only frontmatter unless a tool needs more;
those two are the only fields every tool understands. Supporting files go next
to `SKILL.md`, in `scripts/`, `references/` or `assets/`, and are referred to by
relative path from the skill.

Then list the skill in `.claude-plugin/marketplace.json` and run
`./scripts/validate.sh`. See the README for the full steps.
