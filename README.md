# gitea-fat-runner

A Docker image that bundles the [Gitea runner](https://github.com/go-gitea/gitea-runner) with a full **Docker-in-Docker** (DinD) stack, so CI jobs can run `docker` commands inside themselves.

## Why this exists

The official Gitea runner runs on Ubuntu and has the `gitea-runner` binary only — no Docker daemon. If your workflow needs to build or test containers, it fails with "command not found". This image ships dockerd, containerd, runc, buildx, and all supporting tooling so every job gets a working Docker environment out of the box.

## What's inside

| Component                                                 | Source                                         |
| --------------------------------------------------------- | ---------------------------------------------- |
| OS + runner binary                                        | `docker.gitea.com/runner-images:ubuntu-latest` |
| dockerd / containerd / runc / buildx / ctr / docker-proxy | copied from `docker:dind` (multi-stage)        |
| iptables, fuse-overlayfs, uidmap                          | installed via apt for storage & networking     |

The entrypoint starts `dockerd` with **fuse-overlayfs** as the storage driver, waits for it to come up, then registers an ephemeral runner and execs into daemon mode.

## How to use it

### Docker Compose

For a persistent runner with DinD, mount the host's time files and use `privileged` mode so the inner dockerd can manage containers correctly. Set `GITEA_RUNNER_EPHEMERAL=1` to auto-deregister after each job. `tmpfs` on `/data` prevents creation of orphane volumes.

```yaml
services:
  runner:
    image: gitea-fat-runner:latest
    network_mode: bridge
    privileged: true
    restart: always
    tmpfs:
      - /data
    environment:
      GITEA_RUNNER_EPHEMERAL: "1"
      GITEA_INSTANCE_URL: https://gitea.example.com
      GITEA_RUNNER_REGISTRATION_TOKEN: your-token
      GITEA_RUNNER_NAME: my-runner
      GITEA_RUNNER_LABELS: docker,fuse-overlayfs
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
```

To clean up the gitea runner-list from offline entries by the ephemeral run you may use a sidecar like that:

```yaml
runner-prune:
  image: mariadb:11
  container_name: gitea-runner-prune
  network_mode: docker_bridge
  restart: unless-stopped
  depends_on:
    - gitea
  tmpfs:
    - /var/lib/mysql   # satisfies mariadb's declared VOLUME -> no orphan anon volume
  environment:
    DB_HOST: your-db-host
    DB_PORT: "3306"
    DB_NAME: name
    DB_USER: user
    DB_PASS: pass
    OFFLINE_SECONDS: "3600"   # only prune runners offline > 1h
    INTERVAL_SECONDS: "900"   # run every 15 min
  entrypoint:
    - /bin/sh
    - -c
    - |
      echo "[prune] started; interval=$${INTERVAL_SECONDS}s offline=$${OFFLINE_SECONDS}s"
      while true; do
        OUT=$$(mariadb -h "$$DB_HOST" -P "$$DB_PORT" -u "$$DB_USER" -p"$$DB_PASS" --skip-ssl -N -B "$$DB_NAME" -e \
          "DELETE FROM action_runner WHERE ephemeral = 1 AND id NOT IN (SELECT runner_id FROM action_task WHERE runner_id IS NOT NULL) AND last_online < (UNIX_TIMESTAMP() - $$OFFLINE_SECONDS); SELECT ROW_COUNT();" 2>&1) \
          && echo "[prune] $$(date -u '+%Y-%m-%dT%H:%M:%SZ') removed $$OUT runner(s)" \
          || echo "[prune] $$(date -u '+%Y-%m-%dT%H:%M:%SZ') ERROR: $$OUT" >&2
        sleep "$$INTERVAL_SECONDS"
      done
```

## Environment variables

Gitea standard envs are used + `GITEA_INSECURE_REGISTRIES` is baked in.

| Variable                          | Required | Default  | Description                                                                                       |
| --------------------------------- | -------- | -------- | ------------------------------------------------------------------------------------------------- |
| `GITEA_INSTANCE_URL`              | yes      | —        | URL of your Gitea instance (e.g. `https://gitea.example.com`)                                     |
| `GITEA_RUNNER_REGISTRATION_TOKEN` | yes      | —        | Registration token from the Gitea admin panel                                                     |
| `GITEA_RUNNER_NAME`               | no       | hostname | Human-readable runner name                                                                        |
| `GITEA_RUNNER_LABELS`             | no       | —        | Comma-separated labels (e.g. `docker,fuse-overlayfs`) used for job routing                        |
| `GITEA_INSECURE_REGISTRIES`       | no       | empty    | Comma-separated list of registries allowed over HTTP (passed to dockerd as `--insecure-registry`) |
| `GITEA_RUNNER_EPHEMERAL`          | no       | —        | Set to `"1"` for ephemeral mode (auto-deregister after each job)                                  |

## How the entrypoint works

1. Cleans up stale Docker PID files
2. Parses `GITEA_INSECURE_REGISTRIES` into dockerd flags
3. Starts `dockerd` with `fuse-overlayfs`, backgrounded, logging to `/var/log/dockerd.log`
4. Polls `docker info` for up to 30 seconds until the daemon is ready
5. Registers an **ephemeral** runner (`--no-interactive --ephemeral`) against the Gitea instance
6. Execs into `gitea-runner daemon`, which picks up jobs from the queue

## Building

```bash
docker build -t gitea-fat-runner:latest .
```

## Extending

Add more system packages in `Dockerfile` via `apt-get install`.