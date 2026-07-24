# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89

###############################################################################
# Stage 1 — rclone
###############################################################################
FROM rclone/rclone:1.74.4@sha256:c61954aaa32328a5486715dd063a81c7879f5195ad3505cd362deddd509dc4a1 AS rclone

###############################################################################
# Stage 2 — supercronic
#   Renovate bumps SUPERCRONIC_VERSION; the update-supercronic-sha workflow
#   refreshes the per-arch SHA1 ARGs below on the same PR as a committable review
#   suggestion (it discovers them by name, so a new arch ARG is picked up
#   automatically). The checksum build step fails loudly if a bump leaves them stale.
###############################################################################
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS fetch
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.47
ARG SUPERCRONIC_SHA1_AMD64=5bcefed628e32adc08e32634db2d10e9230dbca0
ARG SUPERCRONIC_SHA1_ARM64=639ab81a72771990790df7ee87d9acfe88e5fa83
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) SUPERCRONIC_SHA1="${SUPERCRONIC_SHA1_AMD64}" ;; \
        arm64) SUPERCRONIC_SHA1="${SUPERCRONIC_SHA1_ARM64}" ;; \
        *) echo "ERROR: unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates; \
    SC="supercronic-linux-${TARGETARCH}"; \
    curl -fsSLO "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/${SC}"; \
    echo "${SUPERCRONIC_SHA1}  ${SC}" | sha1sum -c -; \
    install -m 0755 "${SC}" /usr/local/bin/supercronic

###############################################################################
# base — lean final image (no HTTP client).
# Slim base provides GNU tar/gzip/coreutils/util-linux(flock).
###############################################################################
FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS base

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=fetch  /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY tarclone /usr/local/bin/tarclone
RUN chmod 0755 /usr/local/bin/rclone /usr/local/bin/supercronic /usr/local/bin/tarclone \
 && mkdir -p /etc/backup

# Default to a non-root user. This is only the default: override at runtime with
# `docker run --user` or compose `user:` (must be able to read the backup
# source), no rebuild required.
USER 1500:1500

EXPOSE 9746
ENTRYPOINT ["/usr/local/bin/supercronic", "-prometheus-listen-address", "0.0.0.0:9746", "/etc/backup/crontab"]

###############################################################################
# http-client — extends base with curl for external heartbeat pings (TARCLONE_PING_URL).
# Build with `--target http-client`; publish as <version>-http-client.
###############################################################################
FROM base AS http-client
USER root
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl; \
    rm -rf /var/lib/apt/lists/*
USER 1500:1500
