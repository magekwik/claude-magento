---
name: review
description: Review a diff, branch, or GitHub PR for Magento-specific defects using the magento:code-reviewer agent. Usage: /magento:review [branch|PR-number] [--comment]
---

# /magento:review

Arguments given: `$ARGUMENTS`

## 1. Resolve what to review

- Run `git rev-parse --show-toplevel`. If it fails: say `not a git repository` and stop.
- Parse the arguments:
  - empty → **local** mode
  - an integer → **PR** mode (`N`)
  - any other single word → **branch** mode
  - `--comment` is allowed only together with a PR number; otherwise say `--comment requires a PR number` and stop.
  - anything else → print `usage: /magento:review [branch|PR-number] [--comment]` and stop.
- **local**: determine the base branch:
  `base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')`; if empty, use `main` if `git show-ref --verify --quiet refs/heads/main` succeeds, else `master`.
  Diff = output of `git diff "$base"...HEAD`, then `git diff --cached`, then `git diff`, concatenated. Touched files = union of `git diff --name-only "$base"...HEAD`, `git diff --cached --name-only`, `git diff --name-only`, and `git ls-files --others --exclude-standard` (for untracked files, include their full content in the diff section under a `+++ <path> (untracked)` header).
- **branch**: `git rev-parse --verify <branch>` must succeed, else say `unknown branch: <branch>` and stop. Diff = `git diff <branch>...HEAD`; files = `git diff --name-only <branch>...HEAD`.
- **PR**: `gh --version` and `gh auth status` must both succeed; if not, say `GitHub CLI is missing or not authenticated — run: gh auth login` and stop. Diff = `gh pr diff N`; files = `gh pr diff N --name-only`.
- If the diff is empty: say `Nothing to review.` and stop.

## 2. Dispatch the reviewer

Call the Agent tool with `subagent_type: "magento:code-reviewer"` and this prompt, placeholders filled:

```
Review this Magento 2 change. Mode: <local | branch NAME | PR #N>.

Touched files:
<one path per line>

Read ${CLAUDE_PLUGIN_ROOT}/skills/conventions/SKILL.md first, then these hub skills: <list>.
Hub selection rule you were dispatched with: module for etc/di.xml, etc/events.xml, Plugin/, Observer/, Console/, Controller/; data for db_schema.xml, db_schema_whitelist.json, Setup/Patch, Model/ResourceModel, Api/Data; api for webapi.xml, GraphQl/, Api/, etc/acl.xml; frontend-luma or frontend-hyva for view/frontend and app/design (frontend-hyva if any theme in app/design has parent Hyva/default or composer.lock lists hyva-themes/, else frontend-luma); quality for Test/.

Return findings in your fixed output format only.

Diff:
<diff>
```

## 3. Present the result

- Print the agent's output verbatim — every finding block and the `Verdict:` line. Do not summarise or soften it.
- If `--comment` was given (PR mode only): for each finding line matching `[sev] path:LINE — rule`, post an inline comment:
  ```
  sha=$(gh pr view N --json headRefOid -q .headRefOid)
  gh api repos/{owner}/{repo}/pulls/N/comments -f commit_id="$sha" -f path="<path>" -F line=<LINE> -f side=RIGHT -f body="**[<sev>] <rule>**
  Why: <why>
  Fix: <fix>"
  ```
  Then post the `Verdict:` line with `gh pr comment N --body "<verdict>"`. Report how many inline comments were posted and any that failed (a line outside the diff makes the API reject the comment — fall back to including that finding in the verdict comment).
