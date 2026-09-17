---
name: review
description: "Review a diff, branch, or GitHub PR for Magento-specific defects using the magento:code-reviewer agent. Usage: /magento:review [branch|PR-number] [--comment]"
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
  `mb=$(git merge-base "$base" HEAD)`. Diff = `git diff "$mb" --` (one consistent set of hunk headers covering commits since the base plus staged and unstaged changes). Touched files = `git diff --name-only "$mb" --`.
  Untracked files: for each path from `git ls-files --others --exclude-standard`, append `git diff --no-index -- /dev/null "<path>"` to the diff (standard `@@ -0,0 +1,N @@` hunk headers with `+` lines; its exit code 1 is normal, not an error) and add the path to touched files.
- **branch**: `git rev-parse --verify <branch>` must succeed, else say `unknown branch: <branch>` and stop. `mb=$(git merge-base <branch> HEAD)`. Diff = `git diff "$mb" --`; files = `git diff --name-only "$mb" --`.
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
- If `--comment` was given (PR mode only): for each finding line matching `[sev] path:LINE — rule`, post an inline comment. Write the body to a temp file and pass it by reference so backticks and `$vars` in `<why>`/`<fix>` never get shell-interpolated:
  ```
  sha=$(gh pr view N --json headRefOid -q .headRefOid)
  tmp=$(mktemp)
  printf '%s\n' "**[<sev>] <rule>**" "Why: <why>" "Fix: <fix>" > "$tmp"
  gh api repos/{owner}/{repo}/pulls/N/comments -f commit_id="$sha" -f path="<path>" -F line=<LINE> -f side=RIGHT -F body=@"$tmp"
  ```
  Then post the `Verdict:` line the same way: write it to a temp file and run `gh pr comment N --body-file "$tmp"`. Report how many inline comments were posted and any that failed (a line outside the diff makes the API reject the comment — fall back to including that finding in the verdict comment).
