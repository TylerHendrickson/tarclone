# tarclone

[![CI](https://github.com/TylerHendrickson/tarclone/actions/workflows/ci.yml/badge.svg)](https://github.com/TylerHendrickson/tarclone/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TylerHendrickson/tarclone?sort=semver)](https://github.com/TylerHendrickson/tarclone/releases)
[![GHCR](https://img.shields.io/badge/image-ghcr.io-2496ED?logo=docker&logoColor=white)](https://github.com/TylerHendrickson/tarclone/pkgs/container/tarclone)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A small, single-purpose script that archives a source directory to a dated, rotating `tar.gz` on any rclone remote.
Runs natively on GNU Linux; Docker images provided for portability, with out-of-the-box scheduling and Prometheus metrics.

## Why?

I wanted a fully-containerized backup solution that I could ship within a Docker Compose
stack instead of installing and configuring a scheduled backup service on every host.
It targets small environments running Docker where you value convenience (or just
don't want to mess with what works) and want an easy way to make periodic
(cron-scheduled) offsite backups of your containers' volumes.

In other words, it's ideal for home labs and other stacks built on little more than
Docker atop a minimally-customized OS. The point is painless recovery: if your host
(or its disk) fails, you can restore a recent tarclone backup on a fresh machine to
get the same Docker Compose stack running again — without reconfiguring cron or
installing anything on the host OS beyond Docker itself.

Of course, if you don't use containers, prefer to schedule with system cron, or just
need ad-hoc backups, it works fine as a simple standalone backup solution.

It pairs well with tools like Ansible or Packer: provision a host with Docker Compose,
ship your `docker-compose.yml` alongside your other project files, and tarclone backs
up the data your containerized stack writes. To restore, provision a fresh host the
same way and unpack a recent tarclone backup.

In short, tarclone backs up your entire Docker Compose stack (and runs *in* that same stack)
for maximum portability.

tarclone doesn't try to reinvent the wheel. It's essentially duct tape around
well-established tools — `tar` for archiving, `rclone` for moving the result offsite —
wrapped in a pleasant experience for running it periodically in Docker (via Supercronic),
with metrics for observability included by default.

## How to Use

### Prerequisites

To run outside Docker, you need a Linux host with the following installed:
- `tarclone`
- `bash` 4.4 or newer
- [`rclone`](https://rclone.org/), installed and configured
- GNU `tar` (uses `--numeric-owner`, `--acls`, `--xattrs`) and `gzip` (or set `TARCLONE_COMPRESS_PROG`)
- GNU coreutils (`stat -c`, `sha256sum`, `date`), GNU findutils (`find -readable`), and `flock` (util-linux)
- `curl` or `wget` — only if you use the optional heartbeat pings

These typically ship by default on mainstream Linux distributions.
Non-GNU platforms (macOS/BSD) aren't officially supported for bare-metal use;
for those environments, run the Docker image instead, which bundles everything.

Run `tarclone --check` to verify the required commands are present,
or `tarclone --show-config` to print the resolved configuration;
see `tarclone --help` for all options.

### Configuration

`tarclone` reads all of its config from the environment.
See [`example/tarclone.env`](./example/tarclone.env) for the available variables.
To load them from a file, you must export it before running,
e.g. `set -a; source tarclone.env; set +a` or another tool/convention that loads env vars from a file.

Additionally, if you don't already have one, you'll need to create your own `rclone.conf` file
in order to configure the rclone target named by the `TARCLONE_REMOTE` environment variable,
which controls where `tarclone` will copy your backups using rclone.

### Quickstart example

```shell
# configure rclone:
$ cp example/rclone.conf rclone.conf
# configure tarclone in your environment:
$ cp example/tarclone.env tarclone.env
$ set -a; source tarclone.env; set +a
# at minimum, these two config values are required:
export TARCLONE_REMOTE=my-remote-destination \
  TARCLONE_SOURCE=/path/to/important/stuff
# run tarclone:
$ ./tarclone
```

Congratulations!
You now have a backup of `/path/to/important/stuff` in your rclone remote named `my-remote-destination`.

### Running in Docker

#### Configuration

See the `docker-compose.yml` example to get started. You'll want to bind-mount the following files:
- `crontab`: Defines the cron (via Supercronic) schedule. Copy from [`example/crontab`](./example/crontab) to get started.
- `tarclone.env`: Config lives here. Copy from [`example/tarclone.env`](./example/tarclone.env) to get started.
- `rclone.conf`: Normal `rclone` config file. Copy from [`example/rclone.conf`](./example/rclone.conf) to get started.

> [!IMPORTANT]
> Because `rclone.conf` is mounted as a secret (a non-default path), `RCLONE_CONFIG` **must** point rclone
> at it, e.g. `/run/secrets/rclone_conf` — see the compose example. Mount it at rclone's default location
> instead and you can omit `RCLONE_CONFIG`.

#### Run It

```bash
cp example/tarclone.env tarclone.env  # make sure to customize this!
docker compose up -d
docker compose logs -f tarclone
```

Trigger an immediate run without waiting for schedule:

```bash
docker compose exec tarclone /usr/local/bin/tarclone
```

Confirm a dated `<prefix>_<timestamp>.tar.gz` lands on the share.

### Permissions

As a backup solution, it needs permission to read everything in the backup path.
The example `docker-compose.yml` file demonstrates recommended configuration with minimal privileges.
`DAC_READ_SEARCH` is required to allow detection of unreadable files in the backup source path,
which is recommended so you don't silently skip unreadable files only to discover they're missing
from your backups when you need to restore.

#### Metrics & alerting

##### Prometheus

[Supercronic](https://github.com/aptible/supercronic) serves Prometheus metrics on `:9746` in the container.
Expose it with `docker run -p 9746` (or `ports` mappings if using Docker Compose)
or don't expose the port at all if you don't use Prometheus.

Scrape it:

```yaml
scrape_configs:
  - job_name: tarclone
    static_configs:
      - targets: ["YOUR_DOCKER_HOST:9746"]
```

The series live in the `supercronic_` namespace (a `currently_running` gauge,
exec/success/fail counters, an execution-time histogram, labeled by command/position/schedule).

Confirm exact names from your own endpoint before pasting into alerts:

```bash
curl -s YOUR_DOCKER_HOST:9746/metrics | grep -E 'supercronic_.*(success|fail|exec)'
```

Monitoring examples:

```
# 1. No successful backup in 26h (heartbeat). increase() is reset-aware, so a
#    normal container restart won't false-positive.
- alert: TarcloneNoRecentSuccess
  expr: increase(supercronic_success_total{command=~".*tarclone.*"}[26h]) == 0
  for: 30m

# 2. A run explicitly failed (includes lock-contention "prior run stuck" and timeouts).
- alert: TarcloneRunFailed
  expr: increase(supercronic_fail_total{command=~".*tarclone.*"}[26h]) > 0

# 3. supercronic / container / host is down — counters can't speak to this.
- alert: TarcloneExporterDown
  expr: up{job="tarclone"} == 0
  for: 15m
```

> [!NOTE]
> There is **no last-success timestamp** metric; the heartbeat is expressed on counters.

##### Optional external heartbeat

For an independent check from outside Prometheus monitoring, set a ping URL (e.g. healthchecks.io).
The script GETs `TARCLONE_PING_URL` on a successful backup (URLs specifically for start/fail events are also available):

```
TARCLONE_PING_URL=https://hc-ping.com/<uuid>
TARCLONE_PING_URL_START=https://hc-ping.com/<uuid>/start     # optional
TARCLONE_PING_URL_FAILURE=https://hc-ping.com/<uuid>/fail    # optional
```

Pings are best-effort and never change the backup's exit code.
Requires the `-http-client` image variant, which bundles `curl` for the pings.

#### TLS certificates

To keep images small and to reduce churn, images ship without TLS certificates.
If you ever point rclone at an HTTPS backend (S3, B2, WebDAV, Drive),
or if you configure any heartbeat/start/failure pings that target `https://` URLs,
you should bind-mount your certificate store into the container, e.g.:
- `docker run -v /etc/ssl/certs:/etc/ssl/certs:ro ...`
- In your `docker-compose.yml` service: `volumes: [/etc/ssl/certs:/etc/ssl/certs:ro]`

#### Verifying images

Every published image carries a signed [SLSA build provenance](https://slsa.dev/) attestation
and an SPDX SBOM, attached in the registry as OCI referrers keyed to the image digest.

To verify them with the GitHub CLI:

```bash
gh attestation verify oci://ghcr.io/tylerhendrickson/tarclone:latest --owner TylerHendrickson
```

## Features

- **Zero downtime.** tar reads the read-only source directly; nothing is stopped.
  For stronger consistency, `TARCLONE_PRE_HOOK`/`TARCLONE_POST_HOOK` can quiesce an app around the
  archive step (the post-hook always runs, even on failure).
- **Verified upload, atomic publish.** Uploads as `.partial`, optionally reads it
  back to compare sha256, then server-side renames to the final name — so no
  reader or filesystem snapshot ever sees a half-written file. The local copy is
  deleted only after that verification.
- **Full snapshots, not incremental.** Every run writes a complete, standalone `tar.gz`
  (no deduplication or diffing across runs). Each archive restores by itself
  with just `tar`. Note: this means remote usage scales with `(retention count) × (archive size)`.
- **Contention is an error.** If a previous run still holds the lock, a new run
  exits non-zero.
- **Retention** keeps the newest `TARCLONE_RETENTION_COUNT` of the `<prefix>_*` archives.
- **Observable.** Docker images serve Prometheus metrics, with optional healthcheck pings
  throughout the lifecycle.

## Restoring Backups

Download an archive from the share and extract it into the **parent** of the
original source directory — the archive stores the source dir itself as its top
level (e.g. `important-stuff/...`), so it recreates that directory for you:

```bash
# recreates /path/to/important-stuff with original permissions, numeric ownership, ACLs, xattrs, and symlinks
sudo tar --numeric-owner --acls --xattrs -xpzf important-stuff_2026-06-22_040000.tar.gz -C /path/to
```

> [!TIP]
> `sudo` and the `--numeric-owner --acls --xattrs` flags faithfully restore ownership and metadata.
> They can be omitted if you only need the file contents.

## License

MIT — see [LICENSE](LICENSE).
