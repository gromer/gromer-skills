# issue-flow

`issue-flow` takes one or more GitHub issues through a coding session, a review
loop, owner testing, CI, and merge. It uses separate sessions for coding, review,
and testing, and asks you to check the result before it merges. It can work on
issues from another repository when the issue or project instructions identify
the repository where the PR belongs.

## Install and run

This skill needs session tools in the **Claude, ChatGPT, or GitHub Copilot desktop
app**. It does not run in their command-line tools. The
[Claude](references/claude-app.md) guide has been used for real runs. The
[ChatGPT](references/chatgpt-app.md) and
[GitHub Copilot](references/copilot-app.md) guides have not been through a full
run. The three-app flow has not had a full run since those guides were added.

With GitHub CLI 2.99 or later, install for the agent used by your desktop app:

```bash
# Claude desktop app (Code sessions)
gh skill install gromer/gromer-skills issue-flow --agent claude-code --scope user
# ChatGPT desktop app
gh skill install gromer/gromer-skills issue-flow --agent codex --scope user
# GitHub Copilot desktop app
gh skill install gromer/gromer-skills issue-flow --agent github-copilot --scope user
```

In a project folder, invoke `/issue-flow` with one or more issue references, in
the order you want them handled. For example:

```text
/issue-flow 12 repo#12 owner/repo#12 https://github.com/owner/repo/issues/12
```

`12` means an issue in the current folder's repository. `repo#12` uses the same
owner as that repository. An `owner/repo#12` reference or issue URL names both.
If the app does not pass the references to the skill, put them in your message.

## Prepare your project

The flow reads the work repository's `AGENTS.md` or `CLAUDE.md` for project
facts. Include test commands and setup; how to run and remove a separate test
copy, including any owner data and device access; what the agent must never
touch without your approval; review look-fors and project rules; and who may
merge and by which method. The flow asks you for a missing fact rather than
guessing it.

At the start, it asks whether it may merge after owner testing, review, and CI
pass. If the project has no stated merge method and allows more than one, it
asks which to use. If the project keeps your data, it asks whether testing
should use a separate copy of real data, separate empty data, or real data. If
an issue has no manual check-off steps, it asks whether to skip owner testing.
It may also confirm the issue order when it expands a tracking issue or finds
work in another repository. Questions you already answered are skipped.

## Notifications

The Claude desktop app can send its own notification. For ChatGPT and GitHub
Copilot, the flow looks for an executable script at
`~/.config/issue-flow/notify`. It passes one short notification line as the
script's only argument. For example, to send through [ntfy](https://ntfy.sh),
save this script at that path, replace `<your-topic>` with a topic name only you
know, and run `chmod +x ~/.config/issue-flow/notify`:

```sh
#!/bin/sh
curl -fsS -d "$1" "https://ntfy.sh/<your-topic>" > /dev/null
```

If the script is missing or fails, the flow writes the line in its own session
for you to see when you return to the app.
