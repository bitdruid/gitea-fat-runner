#!/bin/sh
set -e

rm -f /var/run/docker.pid /run/docker.pid 2>/dev/null || true

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

gitea-runner register --no-interactive --ephemeral \
  --instance "$GITEA_INSTANCE_URL" \
  --token   "$GITEA_RUNNER_REGISTRATION_TOKEN" \
  --name    "${GITEA_RUNNER_NAME:-$(hostname)}" \
  --labels  "$GITEA_RUNNER_LABELS"

exec gitea-runner daemon
