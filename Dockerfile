FROM alpine:3.24 AS base
RUN apk add --no-cache tzdata yq-go
COPY --chmod=755 refdata-update.sh /usr/local/bin/refdata-update
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint

# Runs the self-check; built explicitly with --target test, the final image does not contain it.
FROM base AS test
RUN apk add --no-cache busybox-extras zip
COPY --chmod=755 test.sh /usr/local/bin/refdata-update-test
RUN refdata-update-test

# Stays root: busybox crond needs it to run the schedule, and the job only writes the mounted refdata directory.
FROM base
# Unhealthy once the last run without failures is older than REFDATA_UPDATE_MAX_AGE_HOURS, so data going stale
# (a moved source, a broken archive) shows up in docker ps and Portainer instead of only in the log.
HEALTHCHECK --interval=5m --start-period=30m \
  CMD test -n "$(find /var/lib/refdata-update/last-success -mmin -$((${REFDATA_UPDATE_MAX_AGE_HOURS:-36} * 60)) 2>/dev/null)"
ENTRYPOINT ["/usr/local/bin/entrypoint"]
