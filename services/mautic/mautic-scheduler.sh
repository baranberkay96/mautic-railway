#!/bin/bash
# Mautic's cron jobs, run inside the web container (they need the same
# config/local.php, media and import files as the web server).
#
# Each job runs when its interval has passed since its last run, one job at
# a time, so a long job never overlaps itself. All jobs run once shortly
# after start. Intervals follow Mautic's recommended cron setup.
set -u
cd /var/www/html || exit 1

JOBS=(
  "900 mautic:segments:update --batch-limit=900"
  "900 mautic:campaigns:update --batch-limit=300"
  "300 mautic:campaigns:trigger"
  "300 mautic:broadcasts:send"
  "300 mautic:import"
  "300 mautic:webhooks:process"
  "900 mautic:contacts:scheduled_export"
  "3600 mautic:reports:scheduler"
)
declare -A last_run=()

log() { printf '%s railway-cron: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

sleep "${MAUTIC_CRON_START_DELAY:-60}"
log "scheduler started (${#JOBS[@]} jobs)"
while true; do
  for job in "${JOBS[@]}"; do
    interval=${job%% *}
    command=${job#* }
    name=${command%% *}
    now=$(date +%s)
    if (( now - ${last_run[$name]:-0} >= interval )); then
      last_run[$name]=$now
      start=$(date +%s)
      # shellcheck disable=SC2086  # command holds the console arguments
      output=$(timeout 3300 php bin/console $command --no-interaction 2>&1)
      code=$?
      summary=$(printf '%s' "$output" | tr -s '\r\n' ' ' | cut -c1-300)
      log "$name finished with exit code $code in $(( $(date +%s) - start ))s: $summary"
    fi
  done
  sleep 20
done
