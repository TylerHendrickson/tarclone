# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32

###############################################################################
# Stage 1 — rclone
###############################################################################
FROM rclone/rclone:1.75.1@sha256:45401ad7410db1d67ffdb58e19059ad20b0d8e0285a60e38bbec55cc1019c7a5 AS rclone

###############################################################################
# Stage 2 — supercronic
#   Renovate bumps SUPERCRONIC_VERSION; the update-supercronic-sha workflow
#   refreshes the per-arch SHA1 ARGs below on the same PR as a committable review
#   suggestion (it discovers them by name, so a new arch ARG is picked up
#   automatically). The checksum build step fails loudly if a bump leaves them stale.
###############################################################################
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS fetch
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.49
ARG SUPERCRONIC_SHA1_AMD64=e63c11a9726b775a6a11801e81af4f3fb926aa68
ARG SUPERCRONIC_SHA1_ARM64=0b6c5bb743e0b0dafed1132198c81807927ac413
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
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS base

COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=fetch  /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY tarclone /usr/local/bin/tarclone
RUN chmod 0755 /usr/local/bin/rclone /usr/local/bin/supercronic /usr/local/bin/tarclone \
 && mkdir -p /etc/tarclone

# Default to a non-root user. This is only the default: override at runtime with
# `docker run --user` or compose `user:`.
USER 1500:1500

EXPOSE 9746
ENTRYPOINT ["/usr/local/bin/supercronic", "-prometheus-listen-address", "0.0.0.0:9746", "/etc/tarclone/crontab"]

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
