# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 — rclone
###############################################################################
FROM rclone/rclone:1.74.4@sha256:c61954aaa32328a5486715dd063a81c7879f5195ad3505cd362deddd509dc4a1 AS rclone

###############################################################################
# Stage 2 — supercronic
#   Renovate bumps SUPERCRONIC_VERSION; the update-supercronic-sha workflow
#   refreshes the two SHA1 ARGs below on the same PR as a committable review
#   suggestion. The checksum build step fails loudly if a bump leaves them stale.
###############################################################################
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df AS fetch
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.47
ARG SUPERCRONIC_SHA1_AMD64=712d2ece75da6f6e530192a151488578153e4e96
ARG SUPERCRONIC_SHA1_ARM64=93323899ddca3f1198f1796a4bf4418ed1e7982e
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
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df AS base

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=fetch  /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY tarclone.sh /usr/local/bin/tarclone.sh
RUN chmod 0755 /usr/local/bin/rclone /usr/local/bin/supercronic /usr/local/bin/tarclone.sh \
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
