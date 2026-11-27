# App guide: Claude desktop app

How to do the six things `SKILL.md` names, in the Claude desktop app.

## Load the tools

The app lists these tools without loading them. Load them together in one ToolSearch call:

`select:mcp__ccd_session__start_session,SendMessage,PushNotification,mcp__ccd_pr__get_status,mcp__ccd_session_mgmt__list_sessions`

If `start_session` isn't there after that, tell the owner this needs the desktop app's session tools, and stop.

## Start a session

Use `mcp__ccd_session__start_session`: initiation `user_asked`, context `fresh`, `use_worktree: true`, `wake_when_done: true`, a short `name` (e.g. `code-<n>`), the brief as `prompt`, and a `background` of the issue, the flow so far and the owner's rules. Write a bold title line and one sentence just before the call.

**Working folder.** If the work repo isn't the current folder, use `start_session`'s option for the working folder. If it has none, start with `use_worktree: false` and have the session make its own worktree, as `SKILL.md` says.

**When the app won't start it.** A session can't start another session from a turn that began with another session's note (for example, the note that a PR just opened). If the next step needs a new session and that's the case:
- Notify the owner to reply in this session. Any short reply works, e.g. "Reply here to start review of PR <pr>".
- When they reply, start the session in that turn.
- Don't say a card was made or that the owner should click anything. No card is made.

## Message a session

Use `SendMessage` with `to` set to the session's id, never its name.

## Wait for a session

Don't wait or poll. `wake_when_done` brings you back with a note when the session ends a turn, quoting the start of its report. The testing session's first turn ends when its form is showing, which is your cue to notify the owner.

## Ask the owner

Use one `AskUserQuestion` call for all the questions in step 0.

## Show a form

Copy this part into the testing session's brief.

> Show the checklist as an inline form with the visualize `show_widget` tool, loading its `read_me` first. Each step must be self-contained inside the form: the setup note (where, which device), the numbered actions, a "Look for" line, Pass / Fail / Skip, and a comment box. Put a progress count at the top. A Submit button sends all results with `sendPrompt` as one message.

## Reporting back

Copy this part into the testing session's brief.

> Send the results to the project manager session with `SendMessage`.

## Notify the owner

Use `PushNotification`. The app has its own, so the owner's notify script isn't needed here.

## Check CI

`mcp__ccd_pr__get_status` (pass the coding session's id) works as well as `gh pr checks`.

## Naming sessions to the owner

Link sessions as `[title](#<session id>)`.
