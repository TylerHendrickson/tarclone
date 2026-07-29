# CLAUDE.md

Guidance for AI agents (and humans) working in this repo. Keep it accurate as
the code evolves.

## What this is

`tarclone` is a single Bash script ([tarclone](tarclone)) that makes dated,
rotating `tar.gz` snapshots of a directory and uploads them to an rclone remote,
plus a Docker image that runs it on a schedule via supercronic. It is intended
to read as a conventional, well-behaved Unix tool. User-facing docs live in
[README.md](README.md); this file is the contributor's-eye view.

## Commands

```sh
shellcheck tarclone test/smoke.sh      # lint (must be clean; CI fails on any finding)
./test/smoke.sh                        # end-to-end test, host mode (needs rclone + GNU tar/flock)
TARCLONE_IMAGE=<ref> ./test/smoke.sh   # same test, exercising a built image
docker build --target base .           # lean image
docker build --target http-client .    # base + curl (for heartbeat pings)
```

The smoke test uses a local rclone remote (`type = local`) and contacts no
network. It is the fast way to confirm a change didn't break the round-trip.

## Style / Design Philosophy / Principles

- **Conventional, not clever.** Prefer boring, idiomatic solutions.
- **Fail loud.** `set -euo pipefail`; validate inputs early; `die` on misconfiguration.
  Loud failures are better than surprises.
- **Don't reimplement platform mechanisms.** Lean on the shell, rclone, tar,
  supercronic, and Docker rather than re-creating what they already do.
- Match the surrounding comment density and naming. Comments explain *why*, not
  what the next line obviously does.

## Conventions worth calling out

- **Config is entirely environment-driven.** Every knob is a `TARCLONE_*` env
  var resolved near the top of the script; see [example/tarclone.env](example/tarclone.env)
  for the full set and descriptions. Run with `--show-config` to dump defaults.
- **`TARCLONE_` prefix is the rule, with one exception.** Everything tarclone
  reads is `TARCLONE_*`. The sole exception is `RCLONE_CONFIG`, which is
  rclone's *own* native variable (rclone reads it directly) — never rename it or
  wrap it. If you add a config var: prefix it, give it a default, document it in
  the example env, **and add it to `dump_config`** or `--show-config` will
  silently omit it.
- **Ping URLs are the only designated secret.** `TARCLONE_PING_URL[_START|_FAILURE]`
  can carry tokens. They are never written to logs (only a labelled outcome is),
  and each supports a `*_FILE` variant that reads the value from a file (for
  Docker/K8s secret mounts). Hooks (`TARCLONE_PRE_HOOK`/`POST_HOOK`) are *not*
  treated as secrets and print verbatim by design.
- **`--show-config` reports, it does not resolve secrets.** It runs before
  `*_FILE` resolution, so a `*_FILE`-provided ping URL is shown as its path, not
  its contents. Keep that ordering (config → derived → `--show-config` dispatch →
  `*_FILE` resolution) intact, and keep its variable order in lockstep with the
  sections in the example env file.
- **CLI stream conventions.** Logs and `--help` go where convention expects:
  requested `--help` to stdout (exit 0); a usage error prints to stderr with
  usage (exit 2); operational logs go to stderr; exit status is 0 only after a
  verified, published upload.

## Docker & CI

- Two image variants from one Dockerfile: `base` (default, lean) and
  `http-client` (`FROM base` + curl), published as `:<tag>` and
  `:<tag>-http-client`. The Dockerfile carries no version strings — versioning
  and OCI metadata come from the build pipeline.
- **Build-once, promote.** [ci.yml](.github/workflows/ci.yml) builds/tests both
  variants on every push/PR and, on `main`, publishes immutable
  `sha-<gitsha>` images. [release.yml](.github/workflows/release.yml) re-tags
  those exact images to version tags with `docker buildx imagetools create` (no
  rebuild), so a released digest is one CI already tested. Tagging a commit CI
  never built fails the promote by design.
- Third-party Actions are pinned to full commit SHAs (Renovate-maintained via
  [.github/renovate.json5](.github/renovate.json5)). Keep them pinned.
- **Supply chain.** The build job (in [ci.yml](.github/workflows/ci.yml)) scans
  each image with Trivy and fails on *fixable* criticals (accepted exceptions go
  in [.trivyignore](.trivyignore) with a rationale), then, on `main`, attaches a
  signed SLSA provenance attestation and an SPDX SBOM as OCI referrers keyed to
  the image **digest**. Referrers (not buildx inline `provenance:`/`sbom:`) are
  deliberate: they leave the image index untouched so the `imagetools` copy stays
  clean, and because they key to the digest, promote carries them to the version
  tags for free. Vulnerability reporting is documented in
  [SECURITY.md](SECURITY.md).

## Before you commit

Run `shellcheck` and the smoke test. Don't commit or push unless asked; if you
are, branch first rather than committing to `main`.
