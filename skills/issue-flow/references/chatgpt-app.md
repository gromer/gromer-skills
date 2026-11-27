# App guide: ChatGPT desktop app

How to do the six things `SKILL.md` names, in the ChatGPT desktop app, where a session is called a thread.

The tool and parameter names below come from the app's own list of its tools, and haven't been tried in a full run. Before the first call to each tool, read its definition as your app shows it. Where the definition differs from this file, follow the definition. If a tool named here is missing, use the fallback given for it; if none is given, tell the owner which tool is missing and stop.

## Start a session

Use `mcp__codex_app__create_thread` with:
- `prompt`: the brief, with the background (the issue, the flow so far and the owner's rules) at the top of it. There is no separate background field.
- `title`: the short name, e.g. `code-<n>`.
- `target`: the form of it that gives the thread its own worktree of the work repo's clone, from `origin/<base>`. Read the tool's definition for the exact shape.

Keep the thread id it returns: every later call needs it.

**If `target` can't make a worktree,** make one first with `mcp__codex_app__create_worktree` (`allowAsync: true`, `ref: origin/<base>`, `name`, and `sourceRoot` set to the clone), check `mcp__codex_app__get_worktree_creation_status` with the operation id until it's done, and point `target` at the new worktree's folder. If that isn't possible either, start the thread in the clone and have it make its own worktree, as `SKILL.md` says.

**Working folder.** For a work repo that isn't the current folder, the worktree's source is that repo's local clone (`sourceRoot`, or the matching part of `target`).

Don't use `collaboration.spawn_agent` for the sessions in this flow. It starts a subagent inside this thread, which the owner can't open on their own.

## Message a session

Use `mcp__codex_app__send_message_to_thread` with the `threadId` and the message as `prompt`.

## Wait for a session

Use `mcp__codex_app__wait_threads` with the thread as the one target and a `timeoutMs` of a few minutes. If it times out and the thread is still working, call it again. When the thread's turn has ended, read its report with `mcp__codex_app__read_thread`.

Don't wait this way on the owner's testing. Once the testing thread reports that its build is reachable and its checklist is showing, notify the owner and end your turn, as stage 3 says.

## Ask the owner

Use `functions.request_user_input_async` with one question for each thing you need answered, each with its choices as `options`. If that tool isn't there, ask in plain chat as one numbered list.

## Show a form

Copy this part into the testing session's brief.

> This app's question tool takes a title and choices, and has no comment box. So show the checklist in two parts:
> 1. Write the checklist in chat as a numbered list. Each step has its setup note (where, which device), its numbered actions and a "Look for" line.
> 2. Call `functions.request_user_input_async` with one question per step, in the same order. The title is "Step <number>: <a few words>" and the options are Pass, Fail and Skip.
>
> After the owner answers, ask in chat, once, for a short comment on each step they failed or skipped, and anything else they noticed.
>
> If that tool isn't there, show only the numbered list and ask the owner to reply with a line per step, such as "1 pass, 2 fail: the total was wrong, 3 skip".

## Reporting back

Copy this part into the testing session's brief, filling in this thread's id if you know it.

> End your turn with the full results report as your last message. If you were given the project manager's thread id, also send it the report with `mcp__codex_app__send_message_to_thread`. Then tell the owner to go back to the project manager's thread and say testing is done.

When the owner says testing is done, read the testing thread's latest report with `mcp__codex_app__read_thread`, whether or not a message from it reached you.

## Notify the owner

The app has no tool for this. Use the owner's notify script, as the "Notifications" section of `SKILL.md` says. Don't use a mail, chat or automation tool to notify the owner unless they tell you to in this session.

## Check CI

Use `gh pr checks`.

## Naming sessions to the owner

Give the thread's title, e.g. "open the `test-<pr>` thread in the sidebar".
