#!/bin/sh
# Runs refdata-update and retries a failed run 4 times, 15 minutes apart, so a short outage of a source
# does not keep the old data until the next scheduled run.
set -u

# Overridable so test.sh can run it without the real job and without the wait.
update=${REFDATA_UPDATE_BIN:-/usr/local/bin/refdata-update}
delay=${REFDATA_RETRY_DELAY_SECONDS:-900}

for retry in 1 2 3 4; do
  "$update" && exit 0
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') refdata-update: retry $retry of 4 in ${delay}s"
  sleep "$delay"
done
exec "$update"
