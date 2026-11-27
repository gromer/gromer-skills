# App guide: GitHub Copilot app

How to do the six things `SKILL.md` names, in the GitHub Copilot app.

The tool and parameter names below come from the app's own list of its tools, and haven't been tried in a full run. Before the first call to each tool, read its definition as your app shows it. Where the definition differs from this file, follow the definition. If a tool named here is missing, use the fallback given for it; if none is given, tell the owner which tool is missing and stop.

## Start a session

Use `create_session` with:
- `name`: the short name, e.g. `code-<n>`.
- `kickoff`: the brief, with the background (the issue, the flow so far and the owner's rules) at the top of it. There is no separate background field.
- `workspace_type: "worktree"` and `base_branch: <base>`.
- `notify_on_idle: true` and `coordinate_with_creator: true`, so that you hear when it ends a turn.

Keep the session id it returns: every later call needs it.

**Working folder.** For a work repo that isn't this session's project, read the definition of `create_session` (`project_id`) and of `open_issue_session` (`target_repo`) for a way to start the session in that repository. If neither can, start the session without a worktree and have it make its own in the clone, as `SKILL.md` says.

`open_issue_session` and `open_pr_session` also start sessions, tied to an issue or a PR. Use them only if their definitions show they give the session its own worktree; otherwise `create_session` is the one that is known to.

Don't use `task` for the sessions in this flow. It starts a subagent inside this session, which the owner can't open on their own.

## Message a session

Use `send_session_message` with the `session_id` and the `message`.

If a session is waiting on a question or a plan approval of its own, it won't read a message. Check with `get_session`. Answer with `answer_session_input` or `respond_to_session_plan_v2` only when the answer is already in the brief or the owner's rules. Anything else is the owner's to answer: notify them and name the session.

## Wait for a session

With `notify_on_idle: true` you are told when the session ends a turn. When you are, read its state and report with `get_session`.

If no notice has come and you need to know, check once with `get_session` or `get_sessions_status`. Don't poll in a loop. If you can't be told and the session is still working, end your turn and tell the owner in one line that you'll carry on when they reply here.

Don't wait on the owner's testing. Once the testing session reports that its build is reachable and its form is showing, notify the owner and end your turn, as stage 3 says.

## Ask the owner

Use one `ask_user` call for all the questions in step 0. Its `requestedSchema` has one property for each question, with the choices as an `enum`.

## Show a form

Copy this part into the testing session's brief.

> Show the checklist as a form with `ask_user`. In its `requestedSchema`, each step gets two properties, in order:
> - `step_<number>`: an `enum` of Pass, Fail and Skip. Its title is "Step <number>: <a few words>". Its description holds the setup note (where, which device), the numbered actions and the "Look for" line.
> - `step_<number>_comment`: optional text, titled "Comment on step <number>".
>
> Put how to reach the test build, and that it is the test copy, in `message`.
>
> If the checklist has more than eight steps, or the app refuses the form, split it into several forms of up to five steps each and show them one after another. Say in each `message` which steps it holds, such as "Steps 6 to 10 of 12".

## Reporting back

Copy this part into the testing session's brief, filling in this session's id if you know it.

> End your turn with the full results report as your last message. If you were given the project manager's session id, also send it the report with `send_session_message`. Then tell the owner to go back to the project manager's session and say testing is done.

When the owner says testing is done, read the testing session's latest report with `get_session`, whether or not a message from it reached you.

## Notify the owner

The app has no tool that reaches the owner outside the app. Use the owner's notify script, as the "Notifications" section of `SKILL.md` says.

## Check CI

Use `gh pr checks`.

## Naming sessions to the owner

Give the session's name, e.g. "open the `test-<pr>` session in the sidebar". If you have `navigate_to`, you may also open the session for them when they are in the app.
