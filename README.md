# Deploy and Host Mautic with Railway

Mautic is the open-source marketing automation platform: contacts and segments, email campaigns and newsletters, multi-step campaign workflows, landing pages, forms, lead scoring and website tracking. This template runs Mautic 7 on Railway with MySQL, its cron jobs and queue workers, installed from the command line so the web installer is never exposed.

## About Hosting Mautic

Mautic is a Symfony (PHP) application. Besides the web server it needs scheduled jobs (segment and campaign updates, segment emails, imports, webhooks, reports) and queue workers that send queued emails and process tracking hits. All of them read the same configuration file and media folders, and a fresh install serves a web installer that anyone who finds the URL could complete. This community template pins the official 7.2.2 Apache image and runs Apache, a cron scheduler and the messenger workers under supervisord in one service, because they share files and a Railway volume belongs to one service. Mautic is installed with the CLI from your variables before Apache starts, data lives on a volume at `/data`, and HTTP API mail transports are added for plans without SMTP.

## Common Use Cases

- Newsletters and segment emails with a drag-and-drop builder
- Automated nurture campaigns triggered by form submissions, page visits or scores
- Landing pages and forms that capture leads into segments
- Website and email tracking for lead scoring and sales handoff
- A self-hosted alternative to HubSpot Marketing, ActiveCampaign or Mailchimp automation

## Dependencies for Mautic Hosting

- Mautic service: Apache + PHP 8.3 (official image), cron scheduler, messenger workers, volume at `/data`
- MySQL 8.4 LTS
- An email provider (Amazon SES, SendGrid, Postmark, Mailgun or Brevo over HTTP API; SMTP on Railway Pro)

### Deployment Dependencies

- [Mautic documentation](https://docs.mautic.org/)
- [Official Docker image](https://github.com/mautic/docker-mautic)
- [Mautic on GitHub](https://github.com/mautic/mautic)

### Implementation Details

| Service | What runs inside | Volume | Port |
|---|---|---|---|
| Mautic | Mautic 7.2.2: Apache, cron scheduler, email/hit/failed queue workers | `/data` (config, media images and files, imports) | 80, public domain |
| MySQL | MySQL 8.4 LTS | `/var/lib/mysql` | private |

**First login**

1. Enter your email in `MAUTIC_ADMIN_EMAIL` when you deploy. The first start installs Mautic (a few minutes).
2. Open `https://{your-domain}/s/login` and sign in as `admin` (`MAUTIC_ADMIN_USERNAME`) with the generated `MAUTIC_ADMIN_PASSWORD` (Variables tab of the Mautic service).
3. Set up email sending under Settings, Configuration, Email Settings (see below), then create a segment, an email and a campaign.

**Admin password.** `MAUTIC_ADMIN_PASSWORD` is checked at every start and replaces the stored password of `MAUTIC_ADMIN_USERNAME` when it differs. Change the variable and redeploy instead of changing it in the app (an in-app change is reset at the next redeploy). A value shorter than 12 characters is ignored with a warning in the deploy log: an existing password stays, and a brand-new install gets a random admin password until you set a valid one.

**Email sending.** Railway allows outbound SMTP only on the Pro plan. This image adds Symfony Mailer's HTTP API transports, so in Email Settings you can use a DSN such as `ses+api://KEY:SECRET@default?region=eu-west-1`, `sendgrid+api://KEY@default`, `postmark+api://TOKEN@default`, `mailgun+api://KEY:DOMAIN@default` or `brevo+api://KEY@default`. Emails are queued in MySQL and sent by the built-in workers.

**Cron jobs.** A scheduler inside the service runs `mautic:segments:update` and `mautic:campaigns:update` every 15 minutes, `mautic:campaigns:trigger`, `mautic:broadcasts:send`, `mautic:import` and `mautic:webhooks:process` every 5 minutes, scheduled exports every 15 minutes and report schedules hourly. Each run is logged with `railway-cron:` in the deploy log.

**Site URL.** `MAUTIC_SITE_URL` (your Railway domain by default) is used in tracking code and links in emails. Set it to your custom domain when you add one.

**Scaling and upgrades.** Keep one Mautic replica (files live on the volume); raise `DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL` for large sends and give MySQL more memory for big contact lists. The stack idles at roughly 0.9 GB RAM, so use the Hobby plan or higher. To upgrade, eject the repo, change the `mautic/mautic` tag and digest in `services/mautic/Dockerfile` and redeploy; database migrations run at start. Back up MySQL first and read the upgrade notes for major versions.

### Why Deploy Mautic on Railway?

Railway runs Mautic and MySQL with HTTPS, private networking and a persistent volume, so a full marketing automation stack is online without managing servers or cron. This template adds pinned versions, a CLI install that never exposes the installer, working cron jobs and queue workers, and API mail transports for every plan.
