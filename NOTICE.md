# NOTICE: Mautic template

This is a community template. It is not made, endorsed or supported by the Mautic project or Railway. The Mautic name is used only to identify the software.

## Components

| Component | Source | License | How it is used |
|---|---|---|---|
| Mautic 7.2.2 (`mautic/mautic:7.2.2-apache@sha256:cb5a72a63c855917c2c6eca65cd368b02d8d491bc135d3834e85ba5d575d789c`) | https://github.com/mautic/mautic, https://github.com/mautic/docker-mautic | GPL-3.0 | Official image used as the base image; source: https://github.com/mautic/mautic/tree/7.2.2 |
| Symfony Mailer bridges (`symfony/amazon-mailer`, `sendgrid-mailer`, `postmark-mailer`, `mailgun-mailer`, `brevo-mailer`, ~7.4.0) | https://github.com/symfony | MIT | Installed with Composer at build time |
| MySQL 8.4 (`mysql:8.4.13@sha256:8c233bad…`) | https://hub.docker.com/_/mysql | GPL-2.0 | Database |

## Files written for this template

`services/mautic/Dockerfile`, `railway-start.sh`, `mautic-scheduler.sh`, `mautic-admin.php` and the documentation were written for this template and are offered under the MIT License. The start script follows the steps of the official image's entrypoints (volume ownership, migrations on start, messenger consumers) but is not copied from them.

## Upstream files checked

- `mautic/docker-mautic` (main): `Dockerfile`, `common/docker-entrypoint.sh`, `entrypoint_mautic_web.sh`, `entrypoint_mautic_cron.sh`, `entrypoint_mautic_worker.sh`, `common/templates/{local.php,mautic_cron,supervisord.conf}`, `examples/basic` (doctrine messenger DSNs)
- `mautic/mautic` 7.2.2: `app/bundles/InstallBundle/Command/InstallCommand.php` (CLI install options), `app/bundles/CoreBundle/Loader/ParameterLoader.php` (MAUTIC_* environment parameters), `app/composer.json` (symfony/mailer 7.4)

## Market templates

The Railway marketplace templates `9yIPIs` (Mautic), `mautic` and `mautic-open-source-marketing-automation` were reviewed for features only. No files or text were copied.
