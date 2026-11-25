# gromer-skills

Agent skills I write, in one place, installable in Claude, ChatGPT/Codex and
GitHub Copilot. Each skill is a folder with a `SKILL.md`, following the open
[Agent Skills](https://agentskills.io) format, which all of those tools read.
The format is shared, but a skill may still need a specific tool to do its
work. The "Works in" column below says where each skill works.

## Skills

| Skill | What it does | Works in | Upload to the Claude apps |
|---|---|---|---|
| [issue-flow](skills/issue-flow/SKILL.md) | Takes GitHub issues from plan to merged PR by running coding, review and owner-testing sessions as a project manager. | Claude desktop app only (it needs the app's session tools) | No. Install it in Claude Code instead; see [In the Claude apps](#in-the-claude-apps-claudeai-and-desktop). |

## Install

Read a skill before you install it. A skill's instructions run with your
agent's permissions.

### With the GitHub CLI (Copilot, Claude Code, Codex)

Needs [GitHub CLI](https://cli.github.com) 2.99 or later. `gh skill` arrived
in 2.90, but before 2.99 it installed Codex skills for `--scope user` into
`~/.codex/skills` instead of `~/.agents/skills`.

In the commands below, replace `<skill>` with a name from the "Skill" column of
the [skills table](#skills). Check the "Works in" column first: a skill that
needs one tool won't do its work in another.

```bash
gh skill preview gromer/gromer-skills <skill>
```

GitHub Copilot:

```bash
gh skill install gromer/gromer-skills <skill> --agent github-copilot --scope user
```

Claude Code:

```bash
gh skill install gromer/gromer-skills <skill> --agent claude-code --scope user
```

Codex and the ChatGPT desktop app:

```bash
gh skill install gromer/gromer-skills <skill> --agent codex --scope user
```

`--scope user` installs for you in every project. Leave it off to install into
the current repository instead. Replace `<skill>` with `--all` to install
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
`/gromer-skills:issue-flow`.

Claude Code doesn't update this plugin on its own, because auto-update is off
for marketplaces like this one unless you turn it on. To update the installed
plugin, run this in your shell:

```bash
claude plugin update gromer-skills@gromer-skills
```

The new version loads in your next session, or after `/reload-plugins` in a
running one. You can also run `/plugin` in Claude Code, open the plugin on the
**Installed** tab and choose **Update now**.

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

This route covers Codex CLI and the ChatGPT desktop app. Add this repository
as a plugin marketplace:

```bash
codex plugin marketplace add gromer/gromer-skills
```

Then install the plugin from it:

```bash
codex plugin add gromer-skills@gromer-skills
```

Start a new session afterwards so the skills load. Instead of the second
command, you can install `gromer-skills` from the plugin browser: `/plugins` in
Codex CLI, or the Plugins Directory in the ChatGPT desktop app. The plugin
carries every skill in this repository, so check the "Works in" column of the
[skills table](#skills) for the ones that work in Codex.

ChatGPT on the web and mobile can't use a marketplace added this way. There, a
plugin has to be
[published to your workspace](https://developers.openai.com/plugins/build/plugins#publish-a-local-plugin-to-your-workspace)
by a workspace admin, or
[submitted to the public plugin directory](https://developers.openai.com/plugins/deploy/submission).
Adding this repository as a marketplace does neither.

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
4. Check it. `./scripts/validate.sh` needs `yq` and `jq`; on macOS, install
   them with `brew install yq jq`.

   ```bash
   ./scripts/validate.sh
   ```

   ```bash
   gh skill publish --dry-run
   ```

5. Commit and push, then cut a release:

   ```bash
   gh skill publish --tag vX.Y.Z
   ```

   Every change to a skill needs a release to reach `gh skill` users, not only
   a new skill. `gh skill install` and `gh skill update` use the latest release
   tag, while the plugin routes follow `main`. Until the release, plugin users
   can get the change and `gh skill` users can't. The release also carries a
   zip for each skill that can be uploaded.

## License

[MIT](LICENSE)
