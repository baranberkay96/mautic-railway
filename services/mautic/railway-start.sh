#!/bin/bash
# Start Mautic on Railway: Apache + cron scheduler + messenger workers.
#
# 1. Check the variables. A bad value never stops the deploy (STANDARD 8.29):
#    PORT falls back to 80, a bad admin email to admin@example.com, and an
#    empty or short admin password never leaves the installer open (a new
#    install gets a random password instead; an existing one is kept).
# 2. Link config, media/images and media/files to the volume at /data.
# 3. Wait for MySQL, then install Mautic from the command line on the first
#    start (the web installer is never reachable) or run the migrations.
# 4. Apply a changed MAUTIC_ADMIN_PASSWORD to the admin user.
# 5. exec supervisord: Apache, mautic-scheduler.sh (cron jobs) and the
#    messenger consumers for the email, hit and failed queues.
set -euo pipefail

APP=/var/www/html
DATA=/data
CONSOLE="php $APP/bin/console"
DEFAULT_PORT=80
DEFAULT_EMAIL=admin@example.com
MIN_PASSWORD=12
MAX_PASSWORD=72

log() { printf '%s railway-start: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
as_www() { su -s /bin/bash www-data -c "$1"; }

# --- 1. variables -----------------------------------------------------------
port=${PORT:-$DEFAULT_PORT}
if ! [[ $port =~ ^[0-9]{1,5}$ ]] || ((port < 1 || port > 65535)); then
  log "PORT='$port' is not a valid port; using $DEFAULT_PORT"
  port=$DEFAULT_PORT
fi
sed -ri "s/^Listen .*/Listen $port/" /etc/apache2/ports.conf
mpms=$(ls /etc/apache2/mods-enabled | grep -c '^mpm_.*\.load$' || true)
if [[ $mpms != 1 ]]; then
  log "WARNING: $mpms Apache MPMs enabled; keeping only mpm_prefork"
  a2dismod -f mpm_event mpm_worker >/dev/null 2>&1 || true
  a2enmod mpm_prefork >/dev/null 2>&1 || true
fi
sed -ri "s/<VirtualHost \*:[0-9]+>/<VirtualHost *:$port>/" /etc/apache2/sites-available/000-default.conf

email=${MAUTIC_ADMIN_EMAIL:-}
if ! [[ $email =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  log "MAUTIC_ADMIN_EMAIL='$email' is not an email address; using $DEFAULT_EMAIL"
  email=$DEFAULT_EMAIL
fi
username=${MAUTIC_ADMIN_USERNAME:-admin}
if ! [[ $username =~ ^[A-Za-z0-9._@-]{3,64}$ ]]; then
  log "MAUTIC_ADMIN_USERNAME='$username' is not valid (3-64 letters, digits, . _ @ -); using admin"
  username=admin
fi
password=${MAUTIC_ADMIN_PASSWORD:-}
if ((${#password} < MIN_PASSWORD || ${#password} > MAX_PASSWORD)); then
  log "WARNING: MAUTIC_ADMIN_PASSWORD must be $MIN_PASSWORD-$MAX_PASSWORD characters (has ${#password})." \
      "An existing password is kept; a new install gets a random admin password nobody knows." \
      "Set a valid MAUTIC_ADMIN_PASSWORD on the service and redeploy to log in."
  password_mode=lock
  password=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
else
  password_mode=set
fi
unset MAUTIC_ADMIN_PASSWORD

site_url=${MAUTIC_SITE_URL:-}
[[ -z $site_url && -n ${RAILWAY_PUBLIC_DOMAIN:-} ]] && site_url="https://$RAILWAY_PUBLIC_DOMAIN"
site_url=${site_url:-http://localhost}

# The official image reads the database name from MAUTIC_DB_DATABASE, Mautic
# itself from MAUTIC_DB_NAME; keep both in step.
export MAUTIC_DB_NAME=${MAUTIC_DB_NAME:-${MAUTIC_DB_DATABASE:-}}
export MAUTIC_DB_DATABASE=${MAUTIC_DB_DATABASE:-$MAUTIC_DB_NAME}
export MAUTIC_DB_PORT=${MAUTIC_DB_PORT:-3306}

# --- 2. volume ----------------------------------------------------------------
mkdir -p "$DATA/config" "$DATA/media/images" "$DATA/media/files" "$DATA/import"
cp -an /opt/railway-seed/config/. "$DATA/config/"
cp -an /opt/railway-seed/images/. "$DATA/media/images/"
cp -an /opt/railway-seed/files/. "$DATA/media/files/"
link() {  # link <app path> <volume path>
  if [[ ! -L $1 ]]; then rm -rf "$1"; ln -s "$2" "$1"; fi
}
link "$APP/config" "$DATA/config"
link "$APP/docroot/media/images" "$DATA/media/images"
link "$APP/docroot/media/files" "$DATA/media/files"
# Like the official image: start from its local.php template (database
# settings read from the environment); the installer completes it.
if [[ ! -f $DATA/config/local.php ]]; then
  cp /templates/local.php "$DATA/config/local.php"
fi
# Mautic's request middleware reads trusted_proxies only from config files,
# not from the environment; without it every page redirects to itself
# (Railway's edge terminates TLS). Write it to parameters_local.php, which
# Mautic merges over local.php, from MAUTIC_TRUSTED_PROXIES.
RW_PROXIES=${MAUTIC_TRUSTED_PROXIES:-} php -r '
  $p = json_decode((string) getenv("RW_PROXIES"), true);
  if (!is_array($p) || [] === $p || array_filter($p, fn ($v) => !is_string($v) || "" === $v)) {
      fwrite(STDERR, "railway-start: MAUTIC_TRUSTED_PROXIES is not a JSON list of CIDRs; using 0.0.0.0/0 and ::/0\n");
      $p = ["0.0.0.0/0", "::/0"];
  }
  file_put_contents("/data/config/parameters_local.php",
      "<?php\n// Written by railway-start.sh from MAUTIC_TRUSTED_PROXIES at every start.\n\$parameters = ".var_export(["trusted_proxies" => array_values($p)], true).";\n");
'
mkdir -p "$APP/var/logs" "$APP/var/tmp"
find "$DATA" "$APP/var" \( ! -user www-data -o ! -group www-data \) -exec chown -h www-data:www-data {} +

# --- 3. database, install or migrate ----------------------------------------
db_ready() {
  timeout 10 php -r 'try { new PDO("mysql:host=".getenv("MAUTIC_DB_HOST").";port=".getenv("MAUTIC_DB_PORT"),
      getenv("MAUTIC_DB_USER"), getenv("MAUTIC_DB_PASSWORD"), [PDO::ATTR_TIMEOUT => 3]); exit(0); }
    catch (Throwable $e) { exit(1); }'
}
attempt=0
until db_ready; do
  attempt=$((attempt + 1))
  if ((attempt >= 120)); then
    log "ERROR: MySQL at $MAUTIC_DB_HOST:$MAUTIC_DB_PORT is not reachable after 10 minutes"
    exit 1
  fi
  ((attempt == 1)) && log "Waiting for MySQL at $MAUTIC_DB_HOST:$MAUTIC_DB_PORT"
  sleep 5
done

installed() {
  php -r "include('$APP/config/local.php'); exit(!empty(\$parameters['db_driver']) && !empty(\$parameters['site_url']) ? 0 : 1);" 2>/dev/null
}
if installed; then
  log "Mautic is installed; running database migrations"
  as_www "$CONSOLE doctrine:migrations:migrate --no-interaction --allow-no-migration"
else
  log "Installing Mautic for $site_url (admin user '$username')"
  printf '%s' "$password" > /tmp/railway-admin-password
  chown www-data:www-data /tmp/railway-admin-password
  chmod 0600 /tmp/railway-admin-password
  # Values go through the environment and a 0600 file instead of being
  # pasted into the command string (the installer only takes CLI options).
  RW_SITE_URL=$site_url RW_EMAIL=$email RW_USERNAME=$username \
    su -s /bin/bash www-data -c "$CONSOLE mautic:install \"\$RW_SITE_URL\" --force --no-interaction \
      --db_driver=pdo_mysql --db_host=\"\$MAUTIC_DB_HOST\" --db_port=\"\$MAUTIC_DB_PORT\" \
      --db_name=\"\$MAUTIC_DB_NAME\" --db_user=\"\$MAUTIC_DB_USER\" --db_password=\"\$MAUTIC_DB_PASSWORD\" \
      --admin_firstname=Admin --admin_lastname=Mautic --admin_username=\"\$RW_USERNAME\" \
      --admin_email=\"\$RW_EMAIL\" --admin_password=\"\$(cat /tmp/railway-admin-password)\""
  rm -f /tmp/railway-admin-password
  if ! installed; then
    log "ERROR: the Mautic installation did not finish; not starting the web server"
    exit 1
  fi
  log "Mautic installed"
  if [[ $password_mode == lock ]]; then
    log "The admin password is random; set MAUTIC_ADMIN_PASSWORD (12-72 characters) and redeploy to log in."
  fi
fi

# --- 4. admin password from the variable --------------------------------------
if [[ $password_mode == set ]]; then
  printf '%s' "$password" > /tmp/railway-admin-password
  RW_USERNAME=$username php /railway/mautic-admin.php < /tmp/railway-admin-password || \
    log "WARNING: could not check the admin password (see above)"
  rm -f /tmp/railway-admin-password
fi
unset password

as_www "$CONSOLE cache:clear --no-interaction" >/dev/null 2>&1 || log "WARNING: cache:clear failed"

# --- 5. processes --------------------------------------------------------------
workers_email=${DOCKER_MAUTIC_WORKERS_CONSUME_EMAIL:-1}
workers_hit=${DOCKER_MAUTIC_WORKERS_CONSUME_HIT:-1}
[[ $workers_email =~ ^[1-9]$ ]] || workers_email=1
[[ $workers_hit =~ ^[1-9]$ ]] || workers_hit=1
cat > /tmp/supervisord.conf <<EOF
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid
user=root

[program:apache]
command=apache2-foreground
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:scheduler]
command=/railway/mautic-scheduler.sh
user=www-data
environment=HOME="/var/www"
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:consume-email]
command=php $APP/bin/console messenger:consume email --time-limit=3600 --memory-limit=256M
user=www-data
numprocs=$workers_email
process_name=%(program_name)s_%(process_num)02d
autorestart=true
startsecs=10
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:consume-hit]
command=php $APP/bin/console messenger:consume hit --time-limit=3600 --memory-limit=256M
user=www-data
numprocs=$workers_hit
process_name=%(program_name)s_%(process_num)02d
autorestart=true
startsecs=10
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:consume-failed]
command=php $APP/bin/console messenger:consume failed --time-limit=3600 --memory-limit=256M
user=www-data
autorestart=true
startsecs=10
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
EOF
log "Starting Apache on port $port, the cron scheduler and the messenger workers"
exec supervisord -c /tmp/supervisord.conf
