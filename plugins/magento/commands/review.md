---
name: review
description: "Review a diff, branch, or GitHub PR for Magento-specific defects using the magekwik-magento:code-reviewer agent. Usage: /magekwik-magento:review [branch|PR-number] [--comment]"
---

# /magekwik-magento:review

Arguments given: `$ARGUMENTS`

## 1. Resolve what to review

- Run `git rev-parse --show-toplevel`. If it fails: say `not a git repository` and stop.
- Parse the arguments:
  - empty → **local** mode
  - an integer → **PR** mode (`N`)
  - any other single word → **branch** mode
  - `--comment` is allowed only together with a PR number; otherwise say `--comment requires a PR number` and stop.
  - anything else → print `usage: /magekwik-magento:review [branch|PR-number] [--comment]` and stop.
- Untracked-file filter (local and branch modes only — PR mode never sees untracked files): an untracked path is reviewed only if ALL of (a) it starts with `app/`, `lib/`, `dev/`, `setup/`, or `pub/` (but not `pub/static/` or `pub/media/`), or it is a root-level `composer.json`, `composer.lock`, `.htaccess`, `nginx.conf*`, `phpcs.xml*`, `phpstan.neon*`, `grunt-config*`, or `Gruntfile*`; (b) it is a text file with one of these extensions: `.php .phtml .xml .js .less .css .scss .graphqls .json .csv .html .yml .yaml .neon .dist .sample .sh .env`; (c) it is ≤ 200 KB. Binary files are never included, regardless of path or extension. Paths that fail the filter are skipped, not added to the diff or touched files, and collected for reporting: after the findings are presented (step 3), print one line, `Untracked files not reviewed: <path>, <path>, …` (omit the line if nothing was skipped).
- **local**: determine the base branch:
  `base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)` — keep it as `origin/<name>` (the local branch of that name may not exist); if empty, use `main` if `git show-ref --verify --quiet refs/heads/main` succeeds, else `master`.
  `mb=$(git merge-base "$base" HEAD)`. Diff = `git diff "$mb" --` (one consistent set of hunk headers covering commits since the base plus staged and unstaged changes). Touched files = `git diff --name-only "$mb" --`.
  Untracked files: for each path from `git ls-files --others --exclude-standard` that passes the untracked-file filter above, append `git diff --no-index -- /dev/null "<path>"` to the diff (standard `@@ -0,0 +1,N @@` hunk headers with `+` lines; its exit code 1 is normal, not an error) and add the path to touched files.
- **branch**: `git rev-parse --verify <branch>` must succeed, else say `unknown branch: <branch>` and stop. `mb=$(git merge-base <branch> HEAD)`. Diff = `git diff "$mb" --`; files = `git diff --name-only "$mb" --`. Untracked files: same handling as local mode — for each path from `git ls-files --others --exclude-standard` that passes the untracked-file filter above, append `git diff --no-index -- /dev/null "<path>"` to the diff and add the path to touched files.
- **PR**: `gh --version` and `gh auth status` must both succeed; if not, say `GitHub CLI is missing or not authenticated — run: gh auth login` and stop. Diff = `gh pr diff N`; files = `gh pr diff N --name-only`.
- If the diff is empty: say `Nothing to review.` and stop.

## 2. Dispatch the reviewer

Call the Agent tool with `subagent_type: "magekwik-magento:code-reviewer"` and this prompt, placeholders filled:

```
Review this Magento 2 change. Mode: <local | branch NAME | PR #N>.

Touched files:
<one path per line>

Read ${CLAUDE_PLUGIN_ROOT}/skills/conventions/SKILL.md first, then these hub skills: <list>.
Hub selection rule you were dispatched with: module for etc/di.xml, etc/events.xml, Plugin/, Observer/, Console/, Controller/; data for db_schema.xml, db_schema_whitelist.json, Setup/Patch, Model/ResourceModel, Api/Data; api for webapi.xml, GraphQl/, Api/, etc/acl.xml; frontend-luma or frontend-hyva for view/frontend and app/design (frontend-hyva if any theme in app/design has a parent starting with Hyva/ — Hyva/default, Hyva/default-csp, … — or composer.lock lists hyva-themes/, else frontend-luma); quality for Test/.

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
