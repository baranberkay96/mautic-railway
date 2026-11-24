# TEMPLATE: Mautic 7.2 Marketing Automation (MySQL, Cron, Workers)

Composer spec. `template.json` is the machine-readable copy.

## Services

| Service | Source | Public | Healthcheck | Volume | Restart |
|---|---|---|---|---|---|
| Mautic | repo `baranberkay96/mautic-railway`, root `/services/mautic` (`FROM mautic/mautic:7.2.2-apache@sha256:cb5a72a6…`, build 2026-11-19, + Symfony Mailer API bridges) | 80 | `/railway-healthz` (installed + MySQL `SELECT 1`; Apache alias outside the docroot), 1200 s | `/data` | ALWAYS |
| MySQL | `mysql:8.4.13@sha256:8c233bad…` (LTS), buffer pool 256M | no | — | `/var/lib/mysql` | ON_FAILURE |

Required input: `MAUTIC_ADMIN_EMAIL`. Generated: `MAUTIC_ADMIN_PASSWORD` (24), MySQL root and user passwords.

## Design

- Rule 3b: upstream runs web, cron and worker as three containers sharing `config/`, `media/` and import files. On Railway they share one service (supervisord: Apache, `mautic-scheduler.sh` as www-data, messenger consumers for `email`, `hit`, `failed`) and one volume `/data` (config, media/images, media/files; seeded from the image with `cp -an`, linked at runtime because the base image declares them as VOLUMEs).
- STANDARD 8.37: `mautic:install --force` from the CLI before Apache starts; with `db_driver` and `site_url` in `local.php` the web installer is closed. If the install does not finish, the start fails (fail closed).
- Later starts: `doctrine:migrations:migrate`, then `mautic-admin.php` (PDO) re-applies `MAUTIC_ADMIN_PASSWORD` only if `password_verify` fails; `cache:clear`.
- `mautic-scheduler.sh`: interval-based (no overlap, all jobs once ~60 s after start): segments:update 15 min, campaigns:update 15 min, campaigns:trigger 5 min, broadcasts:send 5 min, import 5 min, webhooks:process 5 min, contacts:scheduled_export 15 min, reports:scheduler 60 min. Each run logs `railway-cron: <job> finished with exit code N`.
- Behind Railway's edge Mautic redirected every page to itself: its middleware reads `trusted_proxies` only from config files, not env. `railway-start.sh` writes `config/parameters_local.php` from `MAUTIC_TRUSTED_PROXIES` (default all IPv4+IPv6) at every start.
- Apache MPM: `php:apache` disables mpm_event in a lower layer; on Railway it reappears (8.38) → start script removes extra MPMs before Apache starts.
- Messenger: `MAUTIC_MESSENGER_DSN_EMAIL/HIT=doctrine://default` (as in upstream's example) so the consumers have queues to read.
- Mail: `symfony/{amazon,sendgrid,postmark,mailgun,brevo}-mailer` ~7.4.0 added with Composer (Railway SMTP is Pro-only).
- 8.29: PORT → 80, email → admin@example.com, username → admin, password outside 12–72 → lock mode (random on a new install, existing kept), worker counts clamped to 1–9.

## Improvements over market templates

- `9yIPIs` (479 deploys) and `mautic` (137): third-party repos, MySQL 9 innovation releases, `mautic` has no healthcheck and an empty admin password; none of the three runs Mautic's cron jobs or queue workers on Railway, and SMTP-only mail does not work below Pro. This one: pinned LTS MySQL, CLI install with a generated admin password, cron jobs and workers running and logged, API mail transports, one volume for all persistent files.

## Resources

| Service | Idle RAM | Typical | CPU |
|---|---|---|---|
| Mautic | 0.20–0.40 GB measured | 0.5–1.0 GB (Apache + 3 PHP workers; more during sends) | low, bursts on cron |
| MySQL | 0.23–0.28 GB measured | 0.4–0.8 GB | low |

Measured ≈ 0.65 GB idle in total → ≈ $7–12/month + volumes. Minimum plan: Hobby.

## Verification checklist

- `/railway-healthz` 200 and `/s/login` 200 over https; `/installer` does not offer an installation.
- Admin login works; create a contact, a segment and an email.
- Deploy log shows each `railway-cron:` job once with exit code 0 and the consumers running.
- `MAUTIC_ADMIN_PASSWORD=abc` → SUCCESS, warning, old password works.

## Open questions

- Actual email delivery through an API provider not tested (needs the user's provider account).
