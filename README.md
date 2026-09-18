# claude-magento

Claude Code plugins for Magento, by [Magekwik](https://magekwik.com).

| Plugin | Purpose |
|---|---|
| [`magento`](plugins/magento/) | Magento Open Source 2.4 development toolkit — skills, `/magento:init`, `/magento:review`. |

## Install

```
/plugin marketplace add magekwik/claude-magento
/plugin install magento@magekwik
```

## Develop

- Try it in place: `claude --plugin-dir ./plugins/magento`
- Validate: `claude plugin validate ./plugins/magento --strict && claude plugin validate .`
- Unit tests (scripts): `bash tests/run.sh`
- Evals (need a logged-in `claude`): `bash evals/run.sh` — see `evals/README.md`
- Release: `docs/release-checklist.md`


MIT
