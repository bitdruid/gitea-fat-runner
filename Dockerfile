FROM docker:dind AS dind

FROM docker.gitea.com/runner-images:ubuntu-latest
USER root

ENV GITEA_INSECURE_REGISTRIES=""

RUN apt-get update \
    && apt-get install -y --no-install-recommends iptables fuse-overlayfs uidmap \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dind /usr/local/bin/dockerd                  /usr/local/bin/dockerd
COPY --from=dind /usr/local/bin/docker                   /usr/local/bin/docker
COPY --from=dind /usr/local/bin/docker-init              /usr/local/bin/docker-init
COPY --from=dind /usr/local/bin/docker-proxy             /usr/local/bin/docker-proxy
COPY --from=dind /usr/local/bin/containerd               /usr/local/bin/containerd
COPY --from=dind /usr/local/bin/containerd-shim-runc-v2  /usr/local/bin/containerd-shim-runc-v2
COPY --from=dind /usr/local/bin/ctr                      /usr/local/bin/ctr
COPY --from=dind /usr/local/bin/runc                     /usr/local/bin/runc
COPY --from=dind /usr/local/libexec/docker/cli-plugins/docker-buildx \
    /usr/local/lib/docker/cli-plugins/docker-buildx

COPY --from=gitea/runner:latest /usr/local/bin/gitea-runner /usr/local/bin/gitea-runner

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/gitea-runner /usr/local/bin/dockerd

ENTRYPOINT ["/entrypoint.sh"]
