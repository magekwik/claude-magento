# Evals

Behavioural checks for the `magekwik-magento` plugin. Each scenario in `scenarios/<name>/` has:

- `prompt.md` — front matter `fixture: <name>` (a directory under `fixtures/`), then the prompt.
- `setup.sh` (optional) — runs in the work dir before the prompt (e.g. plants a bad diff).
- `assert.sh` — exits non-zero on failure. Env: `WORK` (work dir), `TRANSCRIPT` (captured output), `PLUGIN` (plugin path).

Run all: `bash evals/run.sh` · one: `bash evals/run.sh module-observer`.
Work dirs are kept under `evals/.work/<name>/` for inspection and are git-ignored.

`claude -p` runs with `--dangerously-skip-permissions` because the work dir is a throwaway copy of a fixture we authored; never point the runner at a real project.
Runs also pass `--setting-sources project,local` so the developer's user-level plugins and settings never leak into a scenario; any `setup.sh` that calls `claude -p` itself must pass the same flags.
