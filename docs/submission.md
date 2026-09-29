# Marketplace submission

Third-party plugins are submitted to Anthropic's **community marketplace** (`anthropics/claude-plugins-community`, installed by users as `magekwik-magento@claude-community`). The **official** marketplace (`claude-plugins-official`) is curated by Anthropic at its discretion — there is no application process, and the submission form does not add plugins to it.

## Where to submit

**The Console route is closed.** Confirmed at the network level on 2026-09-29: with every field
filled correctly under **support@magekwik.com / 4KTechnologies Ltd** (an **API plan** org), pressing
*Submit for review* issues

    POST /api/console/organizations/33afa8f9-3e9c-44ac-b7b8-babf73287827/directory/plugin-submissions
    → 403

and the UI shows: "Plugin submissions have moved to claude.ai, so Console can no longer create or
submit them. Submit your plugin from claude.ai instead, or contact the directory team if your
organization cannot use claude.ai." Re-filling the form does not help. Pressing *Submit for review* at
https://platform.claude.com/plugins/submit therefore cannot file. The form still renders and accepts
input; it just cannot submit. Do not use it.

**Which account can submit.** The org lives only in the Console, and the Console cannot file. The
claude.ai side of this machine is signed in as the personal account `kishore.0510@gmail.com` (Max),
whose account menu offers no workspace switcher — an API-plan org does not come with a claude.ai
workspace. So submitting as 4KTechnologies Ltd needs one of: a claude.ai login for
support@magekwik.com, a Claude Team/Enterprise workspace for the company, or the directory team's
help. Submitting from a personal account still lists the publisher as Magekwik (it is read from
`plugin.json`), but the step-4 compliance attestation is then given on behalf of that personal
organisation rather than the company.

- **claude.ai** (the only working route): https://claude.ai/directory/manage → **Submit new** →
  **Plugin bundle**. Five steps: Source → Listing details → Data handling → Compliance → Review and
  submit. Step 1 validates the repository and runs the directory's checks *before* you continue, and
  it saves a draft per browser tab.
- **Write access is required.** The GitHub account connected to the claude.ai account doing the
  submitting must be able to **push** to the repository, or step 1 refuses: "You can't submit this
  plugin yet — the connected GitHub account can't push to this repository." Submit from an account
  whose GitHub connection has write access to `magekwik/claude-magento`.

The review pipeline runs `claude plugin validate` plus automated safety screening. Approved plugins are pinned to a commit SHA in the community catalog and CI bumps the pin automatically as new commits land on the repository. The public catalog syncs nightly, so there can be a delay before the plugin appears in the catalog's `marketplace.json`; check https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json.

## Values to enter (keep in sync with `plugins/magento/.claude-plugin/plugin.json`)

- Plugin name (slug): `magekwik-magento`
- Display name: Magekwik Magento Toolkit
- Description: Magento Open Source 2.4 development toolkit: framework conventions, module/data/API/frontend skills for Luma and Hyvä, project setup (/magekwik-magento:init) and Magento-aware code review (/magekwik-magento:review).
- Category: development
- Author: Magekwik — https://magekwik.com
- Homepage / repository: https://github.com/magekwik/claude-magento (public)
- Plugin path within the repository: `plugins/magento` — **never `.`** (blank = root on the old
  Console form). On the claude.ai form, leave *Plugin path* empty and it reads
  `.claude-plugin/marketplace.json`, offers "magekwik-magento — ./plugins/magento" as a radio
  option, and fills the path itself when you pick it. The repository root is a
  *marketplace* (`.claude-plugin/marketplace.json`); the only plugin manifest lives at
  `plugins/magento/.claude-plugin/plugin.json`, and the reviewer scans exactly the folder submitted.
- Release: `v1.0.1` (slug renamed from `magento` to `magekwik-magento` before first submission)
- License: MIT
- Keywords: magento, magento2, adobe-commerce, php, ecommerce, hyva, luma
- Components: 8 skills, 2 commands, 1 agent, 3 bash scripts. No hooks, no MCP servers, no network calls, no credentials.
- What it writes: `CLAUDE.md` (marked block) and `.claude/rules/magento.md` on `/magekwik-magento:init`; PR comments only with `/magekwik-magento:review N --comment`.
- Pre-submission check: `claude plugin validate ./plugins/magento --strict` → `✔ Validation passed`
  (run 2026-09-21, re-run 2026-09-29).

### What the directory's own validator says (main @ 8d22b9e, 2026-09-29)

**Validation passed** — 7 checks, 3 warnings, 7 policy holds. Passing: repository fetched; 61 files,
610.6 kB, within the size limits; `.claude-plugin/plugin.json` found and valid; 8 skills · 1 agent ·
2 commands; no MCP servers; name and publisher checks passed.

A *policy hold* is not a failure — it routes the finding to a human reviewer. All seven are
documentation prose in skill reference files, flagged by the shape "credential-named token near a
remote URL" (`MCP_FORWARDS_CREDENTIAL_ENV`):

| Flagged | What is actually there |
|---|---|
| `skills/api/SKILL.md` (`TOKEN`, host `www.w3.org`) | The worked REST example at line 143 — `TOKEN=$(curl … https://example.test/rest/V1/tfa/…)`. `www.w3.org` is the XML namespace in the neighbouring snippets (it appears in 16 files). |
| `skills/api/references/acl-and-auth.md` (`sharedSecret`) | A PHP property in the HMAC webhook-validation sample; the value is injected encrypted through `di.xml`. |
| `skills/api/references/graphql.md` (`TOKEN`, `example.test`) | The same documented example host. |
| `skills/data/references/eav.md` (`pass $$`) | The English word "pass" in the attribute-key tables. |
| `skills/ops/references/dev-envs.md` (`PWD`, `<traefik_subdomain>`) | Warden/DDEV placeholders. |
| `skills/quality/references/phpcs.md` (`_COOKIE`, `github.com`) | Line 118 — `$_COOKIE` listed in a table of PHPCS `Security` sniffs. |
| `.claude-plugin/plugin.json` | The aggregate of the above ("reads TOKEN … and can send data off the machine"). |

Nothing in the plugin reads a real credential or makes a network call, so the intended remedy
(`${user_config.KEY}` with `sensitive: true`) does not apply; the holds want a reviewer's eyes, and
the form's own text says documentation-only occurrences need no change.

Two warnings:

- **No icon** — add `.claude-plugin/icon.svg` (square, ≥128 px) or set `icon` in `plugin.json`. Worth
  fixing; it is the one finding that is a genuine gap.
- **Contains a download-and-run command** (2 findings) — `curl -sI https://store.example/ | grep -i
  x-magento` in `skills/ops/references/caching.md`, a verification one-liner in documentation.

After acceptance: update `plugins/magento/README.md` and the repo README install sections to mention `magekwik-magento@claude-community`.

## Submissions

| Date | Form | Reference / status |
|---|---|---|
| 2026-09-21 | Console (platform.claude.com/plugins/submit), org **4KTechnologies Ltd**, account support@magekwik.com | Filed as "Magento Toolkit by Magekwik" minutes before the 1.0.1 slug rename, so its name and description still described `/magento:init` / `/magento:review`. Moved to "In review" on 2026-09-22 and stayed there. **Withdrawn 2026-09-28** to correct the name and command references — the Console gained a Withdraw control, which explicitly permits resubmitting the same repository. |
| 2026-09-28 | Console, same org and account | **Rejected 2026-09-29** (see below). Filed as **"Magekwik Magento Toolkit"**, matching `plugin.json`. Repository `https://github.com/magekwik/claude-magento`, path `plugins/magento`, homepage = `docs/USER-GUIDE.md`, licence MIT, platform **Claude Code** only (Cowork not ticked — untested there), contact support@magekwik.com, privacy-policy URL left blank (the plugin collects nothing). Description and five use cases use `/magekwik-magento:init` and `/magekwik-magento:review`. The folder field went in as `.`, which is what sank it. |
| 2026-09-29 | — | **Rejected.** Reviewer: "We could not find a plugin at the folder you submitted (.). There is no .claude-plugin/plugin.json there, so nothing was scanned. The plugin appears to be in 'plugins/magento'. Please resubmit with the folder that contains the plugin's manifest. If your repo is a marketplace with several plugins, submit each plugin folder separately." Cause is the form field alone — the root holds `marketplace.json`, not a plugin manifest. No repository change is needed: `claude plugin validate ./plugins/magento --strict` passes on v1.0.1. Refile with folder `plugins/magento`. |
| 2026-09-29 | Console → **blocked**, then claude.ai | Refiled the whole form in the Console with path `plugins/magento`; *Submit for review* was refused — submissions have moved to claude.ai. Restarted at https://claude.ai/directory/manage (**Submit new → Plugin bundle**), signed in as the personal **Kishore · Max** account. Step 1 resolved `plugins/magento` from `marketplace.json` and **validation passed** (3 warnings, 7 policy holds — see above). **Not submitted.** First the connected GitHub account could not push to `magekwik/claude-magento`; that cleared after pushing `0be02df`. Draft saved server-side at `claude.ai/directory/manage` (Continue), with repository, folder and branch **locked** to `magekwik/claude-magento` · `plugins/magento` · `main`, so the folder mistake cannot recur on it. Left unsubmitted pending the account question above; a second Console attempt under 4KTech returned the 403 recorded at the top. Note: resuming the draft clears the Data handling answers. |
| 2026-09-29 | claude.ai (`claude.ai/directory/manage`) | **SUBMITTED.** Filed from the personal claude.ai account `kishore.0510@gmail.com`, contact email **support@magekwik.com**. The listing shows the publisher as **"Plugin · by magekwik"**, read from the repository, so the personal account is not visible publicly. Pinned to **v1.0.1 · `e561dee`**, source `magekwik/claude-magento`, **Listed on: Claude Code** only. Status pipeline: Submitted ✓ → **Security scan (current)** → In review → Live. Submission page: `claude.ai/directory/manage/plugins/f956c608-7cbb-48f6-8f5e-f6472cf6aada`. |

## After submitting: what the page shows

The submission page (`claude.ai/directory/manage/plugins/<id>`) carries **Edit**, **Check for new
commits** and **Withdraw submission**, tabs for Overview / Usage / Listing / Review / Versions /
Settings, and a four-stage status: **Submitted → Security scan → In review → Live**.

- **A webhook is connected to the repository.** New commits on the tracked branch (`main`) are picked
  up and scanned automatically; the page reports "no push to the tracked branch yet" until one lands.
- **Auto-publish does not apply**: "no version of this plugin goes live without an Anthropic
  reviewer" — a consequence of the seven policy holds.
- The first submitted version is recorded as **8 skills · 2 commands · 1 agent**.

## Timing, and where the pipeline actually stands

No SLA is published. Observed on 2026-09-28 from `anthropics/claude-plugins-community`:

- **Submitted → In review** was about 7 hours for the first filing.
- **In review → Passed review** takes days to weeks for others; two reported submissions sat in "pending" for 5 weeks and ~3 months.
- **Passed review → listed in `marketplace.json`** is the real bottleneck. The catalog holds 2,282 plugins and has had **no plugin added since 2026-08-21**; the last commit of any kind was 2026-08-24. Nine open issues report the same stall (#1716, #2376, #2381, #2383, #2388, #2391, #2392, #2394, #2396) with **no reply from anyone at Anthropic** on any of them.
- The submission form itself says: "During spin up there may be delays in release into the directory" and "Submitting this form does not guarantee inclusion."

So: expect a review verdict in days-to-weeks, and treat the directory listing as unscheduled. The self-hosted marketplace (`/plugin marketplace add magekwik/claude-magento`) is the install route that works today and needs nothing from Anthropic.
