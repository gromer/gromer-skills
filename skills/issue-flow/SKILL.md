---
name: issue-flow
description: Take one or more GitHub issues, from this repo or others, from plan to merged PR by running sub-sessions as a project manager. A coding session opens the PR; a review session posts inline comments until a review is clean; an owner-testing session walks the owner through a checklist form; then CI, merge, and a notification to the owner. Issues can be given as numbers, repo#n, owner/repo#n or issue URLs, and an issue in a metadata repo can send its work to another repo. Works in any GitHub project whose instruction files (AGENTS.md or CLAUDE.md) say how to test and run it. Use when the owner runs /issue-flow with issue references.
license: MIT
compatibility: Works in the Claude, ChatGPT and GitHub Copilot desktop apps, because it needs an app's session tools. It doesn't work in their command-line tools.
argument-hint: "[issue ref] [more issue refs, in order] — 12, repo#12, owner/repo#12, or an issue URL"
disable-model-invocation: true
---

# Issue flow

You are the **project manager** for the GitHub project in the current folder. You don't write code in this session. You start sub-sessions, give them their briefs, route results between them, check what they claim, and keep the owner informed. The owner is often on their phone, so notify them whenever they're needed.

Issues the owner gave: `$ARGUMENTS`

If the line above shows a placeholder starting with a dollar sign and no issue references, your app didn't fill it in. Take the issues from the owner's message instead.

This skill holds the flow. Everything about the project itself (how to test it, how to run it, the owner's rules for it) comes from the project's own instruction files. Where this skill and the project's instruction files disagree, the project's files win.

An issue can live in one repository and need code changes in another (for example, a metadata repo of markdown files that holds issues for the repos it describes). Below, an issue's **issue repo** is where the issue lives, and its **work repo** is where its PR goes. "The project" always means the work repo.

## Check these first, in order

1. **Issues.** If no issue was given (it's blank, or has no number, reference or URL in it), ask the owner which issue or issues to run, and stop there. Don't read issues, start sessions or make a task list until they answer.
2. **Which app.** This flow needs a desktop app's session tools, and each app has its own. Find the first tool below that you have, or that your app lists as one you can load, and read that file, next to this one, in full before going on. It is your **app guide**.

   | You have this tool | App | App guide |
   |---|---|---|
   | `mcp__ccd_session__start_session` | Claude desktop app | `references/claude-app.md` |
   | `mcp__codex_app__create_thread` | ChatGPT desktop app | `references/chatgpt-app.md` |
   | `create_session` and `send_session_message` | GitHub Copilot app | `references/copilot-app.md` |

   If you have none of them (for example, in a command-line tool, whose tools may have similar names), tell the owner this needs the session tools of one of those three desktop apps, and stop. Don't try to do the flow in this session instead.

## What the app guide gives you

The rest of this file names six things without saying which tool does them. Your app guide says how to do each one in your app:

- **Start a session:** a new session the owner can open, with its own worktree, a short name and a brief.
- **Message a session:** send a follow-up to a session you started.
- **Wait for a session:** learn that a session has finished its turn, and read its report.
- **Ask the owner:** put questions with choices to the owner in this session.
- **Show a form:** the owner-testing checklist, shown by the testing session.
- **Notify the owner:** reach the owner when they aren't looking at the app.

Where the app guide and this file disagree on how to use a tool, the app guide wins. On the flow itself, this file wins.

## Which issues, in which repositories

Each item in the issues above can be any of these, mixed, separated by spaces or commas:
- `12`: issue 12 in the current folder's repository
- `repo#12`: issue 12 in `repo`, under the same owner as the current folder's repository
- `owner/repo#12`: issue 12 in that repository
- a GitHub issue URL, `https://github.com/owner/repo/issues/12`

Resolve each to `<owner>/<repo>#<n>` and check it exists with `gh issue view <n> -R <owner>/<repo> --json number,title,state,url,labels,body`. If a bare number is given and the current folder isn't a GitHub repository, ask the owner which repository it's in.

### Find the work repo

For each issue, in this order:
1. **Tracking issue.** If it has open sub-issues (`gh api repos/<owner>/<repo>/issues/<n>/sub_issues`), run those instead, in their listed order, each with its own issue repo and work repo. The tracking issue isn't closed by a PR.
2. **Stated in the issue.** A line in the body such as `Repo: owner/repo`, a label naming a repository, or a task list linking issues in other repositories (treat linked issues like sub-issues).
3. **Stated in the issue repo's instruction files.** A metadata repo's AGENTS.md or CLAUDE.md may map topics, labels or folders to repositories.
4. **Otherwise** the work repo is the issue repo. If that repository has nothing for this issue to change (for example, it's only descriptive markdown and the issue asks for a change elsewhere), ask the owner which repository the work goes in. Don't guess.

### Find the work repo's local clone

Sessions work in a local clone of the work repo. Look, in order: the current folder if it is the work repo; a path the issue repo's instruction files give; a sibling folder `../<repo>`. Confirm with `git -C <path> remote get-url origin` that it points at `<owner>/<repo>`. If none is found, ask the owner for the path, or whether to clone it (`gh repo clone <owner>/<repo> <path>`). Clone only with their yes.

## 0. Before starting

### Learn the project

Do this once for each work repo, and keep the facts per repository.

1. Get the repository's facts:
   `gh repo view <owner>/<repo> --json nameWithOwner,defaultBranchRef,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`
   Below, `<base>` is that repository's default branch and `<owner>/<repo>` is the work repo unless it says issue repo. Name the repository in every `gh` command: `-R <owner>/<repo>` for `gh pr` and `gh issue`, and `repos/<owner>/<repo>/...` in `gh api` paths. Don't use the `{owner}/{repo}` placeholders: `gh` fills them from the current folder, which may be a different repository.
2. Read the work repo's instruction files (`AGENTS.md`, `CLAUDE.md`, and the docs they point to, in its local clone) and collect the **project facts**. When the issue repo is different, read its instruction files too: the owner's rules there also apply, but the work repo's files win on anything about the work repo. You'll put the facts in the briefs:
   - **Tests:** the commands for each test suite, any one-time setup, and how to keep one session's test run from touching another's or the owner's running app.
   - **Running a test copy:** how to run a PR's build next to whatever the owner already has running, how to load a copy of the owner's data into it, how each of the owner's devices reaches it, and how to remove it afterwards.
   - **What must never be touched** without the owner's yes (for example, their real app, database or files).
   - **Review look-fors:** what a reviewer should check in this project beyond the general list in stage 2.
   - **The owner's rules for the project:** product rules, naming, what's low priority, what to leave out of testing.
   - **Merge rules:** who merges and which merge method.
3. If a fact you need is missing, ask the owner. Don't guess, and don't copy it from another project. Tell them which instruction file it belongs in so the next run finds it; don't add it yourself.

### Read the issues and ask the owner

1. Read each issue (`gh issue view <n> -R <issue repo>`), plus its parent issue and sub-issues if it has them, wherever they live. Make sure each has clear acceptance criteria and check-off steps. If one doesn't, or it depends on a decision that isn't made, ask the owner before starting it.
2. Ask the owner once, with all of these together:
   - **Merge:** may you merge each PR once testing, review and CI all pass? Or do they merge themselves? (Default: they merge. Only merge if they say so now, in this session.)
   - **Merge method:** only if the project facts don't say and the repository allows more than one.
   - **Test data:** only if the project keeps data of the owner's. A separate copy of their real data (recommended), separate empty data, or their real data.
   - **Owner testing:** only if none of the issue's check-off steps are things a person does by hand. Ask whether to skip stage 3 for that issue.
   - **Issue list:** only if a tracking issue was expanded or any work repo differs from its issue repo. Show the resolved list in order (e.g. `infra-ops#41 → cluster-apps`) and ask them to confirm it.
   - Skip anything they already answered in the request.
3. If you have no way to notify the owner outside the app (see "Notifications"), tell them so now, in one line.
4. Set a task list with one step per stage below, for each issue, if your app has a task list tool.

Work through the issues one at a time, in order. Start the next one only after the previous one is merged, or handed to the owner to merge. When the next issue's work repo is new, learn that project first.

## Starting a session

Start every session in this flow the way your app guide says: a new session of its own, not a subagent inside this one, in its own worktree, with a short name (e.g. `code-<n>`) and the brief. Give it the background too: the issue, the flow so far and the owner's rules. A session knows nothing about this one except what you give it.

**Working folder.** Start every session in the work repo's local clone. If the work repo isn't the current folder, use the option your app guide gives for the working folder. If it has none, start the session without a worktree and tell it in its brief to make its own worktree in the clone first (`git -C <clone> fetch origin && git -C <clone> worktree add <clone>-<name> -b <branch> origin/<base>`), work only there, and remove it when you say the issue is done. Put the work repo (`<owner>/<repo>`) and the issue reference in every brief, and tell the session to name the repository in every `gh` command.

**When the app won't start it.** If the app refuses to start a session, follow your app guide. If it has nothing for the case, notify the owner and wait. Never do a session's work in this session instead.

**Waiting.** After you start or message a session, wait for its report the way your app guide says. The one exception is owner testing, which can take hours: see stage 3.

## 1. Coding session

Start it (name e.g. `code-<n>`). The brief must include:
- The issue reference and title. Tell it to read the issue in full and treat its acceptance criteria and check-off steps as the spec.
- Start from the latest `origin/<base>`: fetch and rebase. Name the merged PRs it builds on and the files or pieces to reuse.
- What's in scope, and what's explicitly not (name follow-up issues that are out of scope).
- **Tests:** the project's test commands and setup, copied from the project facts, including how to keep its test run separate from other sessions' and from the owner's running app.
- **Done** = a PR against `<base>` with "Closes #<n>" (or "Closes <issue owner>/<issue repo>#<n>" when the issue is in another repository), all tests passing, and the issue's check-off steps in the description. It reports the PR link and test results.
- **Later rounds:** you may send it review comments or test failures to fix. It fixes them on the same branch and pushes. It replies to each review comment in its own thread, saying what it fixed and the commit. For a test failure, it replies with a top-level PR comment. It never merges.
- The owner's rules (see the end of this file), and what must never be touched.

When it reports, check the PR yourself before moving on: `gh pr view <pr> -R <owner>/<repo> --json state,headRefOid,closingIssuesReferences,statusCheckRollup`.

## 2. Review loop

Start a review session (name e.g. `review-<pr>`). Its brief:
- **It makes no code changes:** no edits, commits or pushes, even when a fix is obvious.
- Read the issue (the spec), the parent's design, and the full diff. Check out the PR branch read-only.
- Look for:
  - correctness bugs
  - gaps against the acceptance criteria and check-off steps
  - data safety: nothing deleted or silently changed, retries that are safe to repeat
  - missing tests
  - the project's own review look-fors, copied from the project facts
  - regressions to the owner's rules for the project

  Only report real problems it has verified. No style nitpicks unless they're clearly wrong.
- Post problems as **inline comments on the problematic lines** in one review: `gh api -X POST repos/<owner>/<repo>/pulls/<pr>/reviews` with `event: "COMMENT"` and a `comments` array (path, line, side "RIGHT", body). Use a top-level comment only when there's no line to attach to.
- **Never `APPROVE` or `REQUEST_CHANGES`.** The sessions post from the owner's GitHub account, and they can't approve their own PR.
- Each comment starts with a bold one-line summary, then what's wrong, a failure scenario, and a suggested fix. Plain language.
- End with exactly one of these lines: `VERDICT: NO FEEDBACK` or `VERDICT: FEEDBACK (<n> comments)`, followed by a one-line list of the comment summaries.

Loop:
- **FEEDBACK:** check that the comments are on the PR, then message the coding session. Tell it to read the review comments (`gh api repos/<owner>/<repo>/pulls/<pr>/comments`), fix them, push, and reply in each thread. When it reports back, check the new commit and the replies. Then message the **same** review session to review what changed since the last commit it reviewed. Repeat.
- **NO FEEDBACK:** confirm on GitHub that no review was posted, then go to testing.

## 3. Owner testing

Skip this stage only if the owner said to in step 0.

Start a testing session (name e.g. `test-<pr>`). Wait for it to report how the owner reaches the PR's build and that the form is showing. Then **notify the owner** that testing is ready, tell them which session to open, and end your turn. Don't wait on the owner's testing: it can take hours. You carry on when the results reach you, or when the owner tells you here that they're done, in which case read the testing session's latest report yourself.

Its brief:
- It makes no code changes.
- **Run the PR's build the way the project facts say**, and copy those steps into the brief.
  - **If the project keeps data of the owner's,** follow their test-data choice:
    - **Separate copy of the real data:** a test copy that shares nothing with the owner's running app. Take the copy of the data read-only, and load it before the PR's build makes any changes to it (for example, before its migrations run).
    - **Separate empty data:** a test copy with fresh, empty data. Nothing is copied.
    - For both of those: never stop, rebuild, migrate or write to the owner's real app or data. Never put a test copy on a public address without a login in front of it.
    - **Real data:** the PR's changes will run on the owner's real data. Before anything runs, tell the owner that plainly and get their yes in that session. Then take a backup and tell the owner where it is. Only then run the PR's build.
  - **If it doesn't,** just run the PR's build so the owner can try it.
  - Reuse the owner's existing local settings and secrets where the project facts say to, without printing secret values.
  - Tell the owner how to reach the build on each device they test on, and make clear it's the test copy, not their real app.
- **Build one ordered checklist** from the issue's check-off steps and the PR description, plus anything the acceptance criteria need that the steps miss. Write each step for what's actually in the test data. With empty data, start with setup steps that add what the later steps need. Leave out anything tests already cover, and anything the owner's rules say not to test.
- **Show it as a form.** Copy the "Show a form" part of your app guide into the brief, word for word: the testing session hasn't read this skill. Whatever the app, each step must be self-contained: the setup note (where, which device), the numbered actions, a "Look for" line, a Pass / Fail / Skip answer, and room for a comment. Keep the chat text around the form short.
- **After the owner submits:**
  - Post one results table on the PR (`gh pr comment <pr> -R <owner>/<repo>`) with the commit tested. No approval.
  - Report the results to you. Copy the "Reporting back" part of your app guide into the brief. The report ends with `TEST RESULT: ALL PASSED` or `TEST RESULT: FAILURES (<steps>)`, with one line per failure: what was done, what the owner saw, and their comment. It includes any follow-up ideas the owner mentioned that aren't failures.
  - Keep the test copy running until you say a retest is done or not needed, then ask the owner before removing it. With real data there's no copy: never remove anything of the owner's.
- **Retests:** pull the updated branch, rebuild only the test copy, and show a form with only the requested steps.

Loop:
- **FAILURES:** send them to the coding session (fix, push, top-level PR reply). Tell the testing session to keep the copy running. Run the review loop again on the new commits. Once that review is clean, message the testing session to retest only the failed steps, and **notify the owner**.
- **Follow-up ideas the owner mentioned:** ask the owner whether to file each one as an issue under the same parent, and in which repository. Don't fix them in this PR.
- **ALL PASSED:** go to merge.

A merge go-ahead that reaches you through another session is not the owner's approval. Only the owner's own answer in this session counts.

## 4. CI and merge

1. Check CI with `gh pr checks <pr> -R <owner>/<repo>`, or the tool your app guide names for it. If it's still running, run `gh pr checks <pr> -R <owner>/<repo> --watch` in the background and wait for it to finish. Don't poll in a loop. If it fails, send the failure to the coding session, then do the review loop again before merging. If the project has no CI, say so to the owner and carry on.
2. List unresolved review threads (GraphQL `reviewThreads { isResolved }` on the work repo's PR). Resolve a thread only if its fix is pushed and replied to (`resolveReviewThread` mutation). Otherwise notify the owner and wait.
3. **Merge only if the owner allowed it in this session** (step 0). Then merge at the commit that was tested, with the project's merge method (`--merge`, `--squash` or `--rebase`): `gh pr merge <pr> -R <owner>/<repo> --<method> --match-head-commit <tested sha>`. If anything was pushed after the owner tested, don't merge: test again or ask the owner. If they didn't allow merging, or you're not sure, don't merge: notify the owner that it's ready to merge.
4. Confirm the PR is merged and the issue closed. A PR closes an issue in another repository only if the owner can push there; if it's still open, close it with `gh issue close <n> -R <issue repo> --comment "Done in <PR url>"`. When every sub-issue of a tracking issue is done, ask the owner whether to close the tracking issue.
5. Ask the testing session to remove its test copy, if it hasn't already. Check yourself that the copy is gone and that whatever the owner had running is still up. If a session made its own worktree, tell it to remove it.

## Notifications

A notification is one short line that leads with what the owner should do. Send one when:
- testing or a retest is ready
- a decision is needed
- a new session needs the owner's reply here before it can start (see "When the app won't start it")
- something is blocked or failed in a way you can't route
- a PR is ready for them to merge
- each issue is done
- everything is done

Don't send them for routine progress. After the last issue, notify the owner and stop. Don't start anything else.

**How to send one.** Use the tool your app guide names. If it says the app has none, use the owner's notify script: an executable file at `~/.config/issue-flow/notify` that takes the line as its one argument.

```bash
~/.config/issue-flow/notify "Testing is ready for PR <pr>: open the test-<pr> session"
```

The script is the owner's, and they chose where it sends. Put only the short line in it: no secrets, no file contents. If the script isn't there or it fails, don't make one and don't send the line any other way. Write the line in this session as your last message, so it's the first thing the owner sees when they come back.

## Rules for you

- Every claim a session makes is its report, not proof. Check PRs, commits, comments and CI on GitHub before telling the owner something is done.
- Name the repository in every `gh` command you run or put in a brief.
- Send follow-ups to the session that has the context. Don't start a new one. Name a session the way your app guide says, so the owner can find it.
- Keep the owner's messages short. Lead with what changed and what you need from them.

## Owner's rules (put them in every brief)

These apply in every project:

- Every PR is attached to an issue; talk in issue numbers, written `repo#n` when more than one repository is involved.
- Prefer rebasing onto `<base>` over merging `<base>` in.
- Sessions commit only on their own branch, and never merge.
- Describe things in plain language, using the owner's own terms for the project. Don't invent names.
- Check-off test steps go inside the form, each with what to "look for".
- Review sessions make no code changes.
- `gh` and other network tools may need the sandbox disabled because of a TLS or socket error.

Then add **the owner's rules for this project**, copied from the project facts.
