# Cron jobs and console commands

*Target: Magento Open Source 2.4.4–2.4.9, PHP 8.1–8.5 (support varies by release).* Rules cited by ID are in `magento:conventions` (P6 for cron; A1, A9 throughout).

## Cron jobs

### How Magento cron works

The system crontab runs `bin/magento cron:run` every minute. Each run, for each cron *group*, Magento generates upcoming rows in the `cron_schedule` table from every job's schedule expression, then executes the rows whose `scheduled_at` has arrived. Jobs are PHP methods named in `crontab.xml`; the class is built by the object manager in the `crontab` area (`etc/crontab/di.xml` and `etc/crontab/events.xml` apply).

`cron_schedule.status` values (`Magento\Cron\Model\Schedule`): `pending` (generated, not yet due) → `running` → `success` | `error` (the method threw; `messages` holds the exception message); `missed` when a pending row's window expired before a runner picked it up (`schedule_lifetime` in the group settings; `messages` says *"Cron Job ... is missed at ..."*). A per-job lock stops two runners executing the same `job_code` at once, and a row left in `running` by a crashed process is flipped to `error` the next time that job is picked up.

### `etc/crontab.xml`

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Cron:etc/crontab.xsd">
    <group id="acme_catalog">
        <job name="acme_catalog_badge_refresh" instance="Acme\Catalog\Cron\RefreshBadges" method="execute">
            <schedule>15 2 * * *</schedule>
        </job>
        <job name="acme_catalog_badge_export" instance="Acme\Catalog\Cron\ExportBadges" method="execute">
            <config_path>acme_catalog/badges/export_cron_expr</config_path>
        </job>
    </group>
</config>
```

- `<group id>`: `default` is the core group where most core jobs live; `index` runs indexers; `consumers` runs queue consumers. Give your own jobs their own group when they are slow or must be scheduled differently (P6).
- `<job name>` is the `job_code` in `cron_schedule`; keep it globally unique (`<vendor>_<module>_<task>`).
- `instance`/`method`: any injectable class and public method; no interface to implement. The runner calls it with the `Magento\Cron\Model\Schedule` row as its only argument; declare no parameters unless you need it.
- `<schedule>` is a five-field cron expression. `<config_path>` reads the expression from system configuration instead (define the path in `etc/config.xml` / `system.xml` — Q6) so admins can change it; use one or the other.

### Job class

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Cron;

use Acme\Catalog\Model\BadgeRefresher;
use Psr\Log\LoggerInterface;

class RefreshBadges
{
    private const BATCH_SIZE = 500;

    public function __construct(
        private readonly BadgeRefresher $refresher,
        private readonly LoggerInterface $logger
    ) {
    }

    public function execute(): void
    {
        $processed = $this->refresher->refreshStale(self::BATCH_SIZE);
        $this->logger->info(sprintf('acme_catalog_badge_refresh: refreshed %d products', $processed));
    }
}
```

Idempotency and bounds (P6):

- Running the job twice, or after a crash mid-way, must be safe: select work by state (`stale`, `pending`, `updated_at < ...`), not by "since the last run", and mark items done as you go.
- Bound each run (page size, time budget) so a backlog never produces a run that outlives `schedule_lifetime`; leave the remainder for the next tick.
- Throw on failure — a thrown exception marks the row `error` with the message; swallowing it marks `success` and hides the problem. Log with a job-name prefix so `var/log/cron.log`/`system.log` are greppable.
- Do not trigger a full reindex from a job — indexers have their own `index` group and *Update by Schedule* (P5); keep the cron area free of request-scoped assumptions (no session, no store context unless you emulate it).

### `etc/cron_groups.xml` — own group and separate process

```xml
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Cron:etc/cron_groups.xsd">
    <group id="acme_catalog">
        <schedule_generate_every>15</schedule_generate_every>
        <schedule_ahead_for>20</schedule_ahead_for>
        <schedule_lifetime>15</schedule_lifetime>
        <history_cleanup_every>10</history_cleanup_every>
        <history_success_lifetime>60</history_success_lifetime>
        <history_failure_lifetime>4320</history_failure_lifetime>
        <use_separate_process>1</use_separate_process>
    </group>
</config>
```

All values are minutes except `use_separate_process` (`1`/`0`). The `default` group in `Magento_Cron` uses exactly these numbers with `use_separate_process` = `0`. Admins can override each per group under *Stores > Configuration > Advanced > System > Cron*.

- `use_separate_process` = `1` makes `cron:run` fork `bin/magento cron:run --group=<id>` for the group, so a long or crashing job cannot stall the `default` group (P6).
- `schedule_lifetime` is how long a pending row may wait past `scheduled_at` before it is marked `missed`; raise it for a group whose jobs legitimately queue behind each other.
- `cron_groups.xml` is required, not optional: the runner reads `system/cron/<group>/<setting>` with no fallback, and those values are seeded only from `cron_groups.xml`. An undeclared group has `schedule_ahead_for` = 0, so no `cron_schedule` rows are ever generated and its jobs never run.

### Running and verifying

```bash
bin/magento cron:run                       # all groups; run twice — the first run only schedules
bin/magento cron:run --group=acme_catalog  # one group (also --exclude-group=<id>)
bin/magento cron:install                   # writes the system crontab entry (once per environment)
```

- Check `cron_schedule`: `SELECT job_code, status, scheduled_at, executed_at, finished_at, messages FROM cron_schedule WHERE job_code LIKE 'acme_%' ORDER BY scheduled_at DESC;`
- Logs: `var/log/cron.log` is the runner's own logger; `var/log/magento.cron.log` is where the crontab entry written by `cron:install` redirects stdout/stderr; `var/log/system.log` gets what the job itself logs through `LoggerInterface`.
- To run a job on demand without waiting for the schedule, call the class from a console command (below) or an integration test; do not set `<schedule>* * * * *</schedule>` in committed code.
- After editing `crontab.xml`/`cron_groups.xml`: `bin/magento cache:clean config`. Stale `pending` rows for a renamed job stay until history cleanup — delete them by `job_code` if they confuse monitoring.

## Console commands

### Command class

Commands extend Symfony's `Command`; `configure()` names it and declares options/arguments; `execute()` does the work and returns an integer exit code — use `Magento\Framework\Console\Cli::RETURN_SUCCESS` (0) / `Cli::RETURN_FAILURE` (1).

```php
<?php
declare(strict_types=1);

namespace Acme\Catalog\Console\Command;

use Acme\Catalog\Model\BadgeRefresher;
use Magento\Framework\App\Area;
use Magento\Framework\App\State;
use Magento\Framework\Console\Cli;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

class BadgeRefresh extends Command
{
    private const OPTION_LIMIT = 'limit';

    public function __construct(
        private readonly BadgeRefresher $refresher,
        private readonly State $appState,
        ?string $name = null
    ) {
        parent::__construct($name);
    }

    protected function configure(): void
    {
        $this->setName('acme:catalog:badge-refresh')
            ->setDescription('Recompute stale product badges')
            ->addOption(self::OPTION_LIMIT, 'l', InputOption::VALUE_REQUIRED, 'Maximum products to process', '500');
        parent::configure();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $limit = (int) $input->getOption(self::OPTION_LIMIT);
        try {
            $processed = $this->appState->emulateAreaCode(
                Area::AREA_ADMINHTML,
                fn (): int => $this->refresher->refreshStale($limit)
            );
        } catch (\Throwable $e) {
            $output->writeln(sprintf('<error>%s</error>', $e->getMessage()));
            return Cli::RETURN_FAILURE;
        }
        $output->writeln(sprintf('<info>Refreshed %d products.</info>', $processed));
        return Cli::RETURN_SUCCESS;
    }
}
```

- `configure()` and `execute()` are `protected`; declare `execute(...): int` and always return an int — 2.4.9 ships Symfony Console 7.x, where the base method is typed `: int`, and earlier 2.4.x (Console 4.4/5/6) accept the typed signature too.
- Keep `parent::__construct($name)`; Symfony needs it. Constructor-inject services (A1, A9); the object manager builds the command, so every dependency must be injectable.
- Options: `InputOption::VALUE_REQUIRED` (takes a value), `VALUE_NONE` (flag), `VALUE_OPTIONAL`, `VALUE_IS_ARRAY`; arguments: `InputArgument::REQUIRED`/`OPTIONAL`/`IS_ARRAY` via `addArgument()`.
- Name commands `<vendor>:<module>:<verb>` so `bin/magento list` groups them.

### Area code

The CLI bootstraps with no area code. Code that reads area-dependent config, renders, or touches design/URLs throws *"Area code is not set"*. Two fixes, in order of preference:

1. `$this->appState->emulateAreaCode(Area::AREA_ADMINHTML, $callback, $params)` — sets the area for the callback and restores it afterwards; safe to call repeatedly.
2. `$this->appState->setAreaCode(Area::AREA_ADMINHTML)` once at the top of `execute()` — throws `LocalizedException` *"Area code is already set"* if anything set it first, so wrap it in `try { } catch (LocalizedException) { }`.

Use `Area::AREA_ADMINHTML` (or `AREA_FRONTEND`/`AREA_CRONTAB`) constants from `Magento\Framework\App\Area`, never string literals. Pure service calls (repositories, resource models) do not need an area.

### Registration in `etc/di.xml`

```xml
<type name="Magento\Framework\Console\CommandListInterface">
    <arguments>
        <argument name="commands" xsi:type="array">
            <item name="acme_catalog_badge_refresh" xsi:type="object">Acme\Catalog\Console\Command\BadgeRefresh</item>
        </argument>
    </arguments>
</type>
```

- Global `etc/di.xml` only (the CLI loads no area). The `item name` is any unique key.
- Every registered command is instantiated on every `bin/magento` invocation — including `cache:clean` in deploy scripts. Inject heavy dependencies as `\Proxy` via `di.xml` (`di-xml.md`) so `bin/magento list` stays fast. A command that cannot be built — its constructor throws, or the `<item>` names a class that does not exist — fails the whole `CommandListInterface`: in developer mode `bin/magento` aborts with the exception; in production mode the error is logged to `var/log/system.log` ("CRITICAL: Core Magento commands ... are unavailable!"), `bin/magento list` shows no Magento commands, and any Magento command exits 1 with "Some commands failed to load" (2.4.9 behaviour; 2.4.8 and earlier abort in every mode).

### Verifying

```bash
bin/magento cache:clean config compiled_config   # developer mode: di.xml is cached; plugin lists in compiled_config
bin/magento setup:di:compile            # production mode only
bin/magento list | grep acme            # command is registered
bin/magento acme:catalog:badge-refresh --limit=50
```

If the command is missing from `list` with no error: the `di.xml` edit is not in the global file, or the config cache is stale. If *every* Magento command is missing or `bin/magento` aborts, one registered command failed to build — see above.

## Cron vs command vs queue

| Need | Use |
|---|---|
| Unattended, recurring | Cron job (this file) |
| Operator-triggered, one-off, deploy step | Console command |
| Triggered by an event, may be slow, must retry | Message queue consumer (`etc/queue_*.xml`; consumers run via the `consumers` cron group) — out of scope here |
| Both scheduled and on demand | Put the logic in a service class; call it from a cron class *and* a command |

## Sources

- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/crons/custom-cron-tutorial — Configure a custom cron job and cron group (`crontab.xml`, `cron_groups.xml` with `use_separate_process`, job class, `cron:run --group`, `cron_schedule` check)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/cli/configure-cron-jobs — Configure and run cron jobs (`cron:install`, `cron:run [--group]`, run twice, `var/log/cron.log`, `cron_schedule`)
- https://experienceleague.adobe.com/en/docs/commerce-operations/configuration-guide/crons/custom-cron — Cron jobs overview (core groups `default`, `index`, `consumers`)
- https://developer.adobe.com/commerce/php/development/cli-commands/custom — Create a custom command (`Command` subclass, `configure()`/`execute(): int`, `commands` array registration, `cache:clean`/`setup:di:compile`, `bin/magento list`)
- https://developer.adobe.com/commerce/php/coding-standards/technical-guidelines — Technical guidelines ("Cron job SHOULD be an idempotent method")
