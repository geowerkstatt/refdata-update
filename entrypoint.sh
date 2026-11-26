#!/bin/sh
# Refreshes the reference data once on start, then on REFDATA_UPDATE_SCHEDULE (cron syntax, in the time zone TZ).
set -eu

schedule=${REFDATA_UPDATE_SCHEDULE:-0 1 * * *}
crontab=/tmp/refdata-update.crontab
echo "$schedule /usr/local/bin/refdata-run" > "$crontab"
echo "refdata-update: scheduled at '$schedule' (TZ ${TZ:-UTC})"

# A failed source is logged and keeps its last state; it must not stop the schedule from starting.
/usr/local/bin/refdata-run || true

exec supercronic "$crontab"
