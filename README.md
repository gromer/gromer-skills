# gromer-skills

Agent skills I write, in one place, installable in Claude, ChatGPT/Codex and
GitHub Copilot. Each skill is a folder with a `SKILL.md`, following the open
[Agent Skills](https://agentskills.io) format, so the same copy works in every
tool.

## Skills

| Skill | What it does | Works in | Upload to the Claude apps |
|---|---|---|---|
| [issue-flow](skills/issue-flow/SKILL.md) | Takes GitHub issues from plan to merged PR by running coding, review and owner-testing sessions as a project manager. | Claude desktop app only (it needs the app's session tools) | No. Install it in Claude Code instead; see [In the Claude apps](#in-the-claude-apps-claudeai-and-desktop). |

## Install

Read a skill before you install it. A skill's instructions run with your
agent's permissions.

### With the GitHub CLI (Copilot, Claude Code, Codex)

Needs [GitHub CLI](https://cli.github.com) 2.90 or later.

```bash
gh skill preview gromer/gromer-skills issue-flow
```

GitHub Copilot:

```bash
gh skill install gromer/gromer-skills issue-flow --agent github-copilot --scope user
```

Claude Code:

```bash
gh skill install gromer/gromer-skills issue-flow --agent claude-code --scope user
```

Codex and the ChatGPT desktop app:

```bash
gh skill install gromer/gromer-skills issue-flow --agent codex --scope user
```

`--scope user` installs for you in every project. Leave it off to install into
the current repository instead. Replace the skill name with `--all` to install
everything.

Update later with:

```bash
gh skill update --all
```

### As a Claude Code plugin

In Claude Code:

```
/plugin marketplace add gromer/gromer-skills
/plugin install gromer-skills@gromer-skills
```

The skills then appear under the plugin's name, for example
`/gromer-skills:issue-flow`. Update with `/plugin marketplace update gromer-skills`.

### In the Claude apps (claude.ai and desktop)

Only some skills can be uploaded. The "Upload to the Claude apps" column of the
[skills table](#skills) says which. The apps reject an uploaded skill whose
frontmatter has any key other than `name`, `description`, `license`,
`compatibility`, `metadata` and `allowed-tools`, so a release carries a zip
only for the skills that pass that rule.

For a skill that can be uploaded:

1. Download `<skill>.zip` from the [latest release](https://github.com/gromer/gromer-skills/releases/latest).
2. Open **Customize > Skills** and upload the zip.
3. Turn the skill on.

`issue-flow` can't be uploaded, and no release has a zip for it. Its
frontmatter has Claude Code-only keys, and it needs the Claude desktop app's
Code session tools. Install it in Claude Code instead, with the GitHub CLI:

```bash
gh skill install gromer/gromer-skills issue-flow --agent claude-code --scope user
```

or [as a Claude Code plugin](#as-a-claude-code-plugin):

```
/plugin marketplace add gromer/gromer-skills
/plugin install gromer-skills@gromer-skills
```

### As a ChatGPT / Codex plugin

ChatGPT on the web and mobile only load skills that come inside a plugin. Codex
can add this repository as a plugin marketplace:

```bash
codex plugin marketplace add gromer/gromer-skills
```

Then install `gromer-skills` from the Plugins Directory in the ChatGPT desktop
app or Codex CLI.

## Adding a skill

1. Create `skills/<skill-name>/SKILL.md`. Start from
   [docs/skill-template.md](docs/skill-template.md). The folder name must match
   the `name` in the frontmatter.
2. Add `"./skills/<skill-name>"` to the `skills` list in
   [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json).
3. Add a row to the table above. In its "Upload to the Claude apps" column say
   "Yes" if the skill's frontmatter has no key other than `name`,
   `description`, `license`, `compatibility`, `metadata` and `allowed-tools`.
   Otherwise say "No": `./scripts/package.sh` skips the skill, and releases
   have no zip for it.
4. Check it:

   ```bash
   ./scripts/validate.sh
   ```

   ```bash
   gh skill publish --dry-run
   ```

5. Commit and push. To cut a release that installs pin to and that carries a
   zip for each skill that can be uploaded:

   ```bash
   gh skill publish --tag vX.Y.Z
   ```

## License

[MIT](LICENSE)
