#!/bin/sh
set -e

rm -f /var/run/docker.pid /run/docker.pid 2>/dev/null || true

# restart: always reuses the container, so wipe the inner docker state for a clean job
rm -rf /var/lib/docker/* 2>/dev/null || true

INSECURE_FLAGS=""
for r in $(echo "$GITEA_INSECURE_REGISTRIES" | tr ',' ' '); do
  [ -n "$r" ] && INSECURE_FLAGS="$INSECURE_FLAGS --insecure-registry $r"
done

dockerd \
  --host=unix:///var/run/docker.sock \
  --storage-driver=fuse-overlayfs \
  $INSECURE_FLAGS \
  >/var/log/dockerd.log 2>&1 &

i=0
while ! docker info >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -ge 30 ]; then
    echo "dockerd failed to start:" >&2
    cat /var/log/dockerd.log >&2 || true
    exit 1
  fi
  sleep 1
done

# optional polling intervals: an idle runner polls every 2s (backoff up to 5s) by default
CONFIG_FLAGS=""
if [ -n "$GITEA_RUNNER_FETCH_INTERVAL$GITEA_RUNNER_FETCH_INTERVAL_MAX$GITEA_RUNNER_FETCH_TIMEOUT" ]; then
  CONFIG_FILE=/tmp/gitea-runner-config.yaml
  echo "runner:" > "$CONFIG_FILE"
  if [ -n "$GITEA_RUNNER_FETCH_INTERVAL" ]; then
    echo "  fetch_interval: $GITEA_RUNNER_FETCH_INTERVAL" >> "$CONFIG_FILE"
    # backoff max must not be below the interval
    echo "  fetch_interval_max: ${GITEA_RUNNER_FETCH_INTERVAL_MAX:-$GITEA_RUNNER_FETCH_INTERVAL}" >> "$CONFIG_FILE"
  elif [ -n "$GITEA_RUNNER_FETCH_INTERVAL_MAX" ]; then
    echo "  fetch_interval_max: $GITEA_RUNNER_FETCH_INTERVAL_MAX" >> "$CONFIG_FILE"
  fi
  if [ -n "$GITEA_RUNNER_FETCH_TIMEOUT" ]; then
    echo "  fetch_timeout: $GITEA_RUNNER_FETCH_TIMEOUT" >> "$CONFIG_FILE"
  fi
  CONFIG_FLAGS="--config $CONFIG_FILE"
fi

gitea-runner $CONFIG_FLAGS register --no-interactive --ephemeral \
  --instance "$GITEA_INSTANCE_URL" \
  --token   "$GITEA_RUNNER_REGISTRATION_TOKEN" \
  --name    "${GITEA_RUNNER_NAME:-$(hostname)}" \
  --labels  "$GITEA_RUNNER_LABELS"

exec gitea-runner $CONFIG_FLAGS daemon
