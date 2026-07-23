#!/usr/bin/env bash
#
# Smoke test: exercise tarclone end-to-end against a local rclone remote
# (no network) and assert the important guarantees hold — the archive is
# published, it round-trips, retention is enforced, and --show-config reports
# the resolved configuration.
#
# Two modes:
#   - host  (default):      runs ./tarclone directly; needs rclone + GNU
#                           tar/flock on the host.
#   - image (TARCLONE_IMAGE=<ref>): runs tarclone inside that image via
#                           docker, so the built image itself is exercised. Only
#                           docker + GNU tar are needed on the host.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tarclone="${here}/../tarclone"
image="${TARCLONE_IMAGE:-}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "SMOKE FAIL: $*" >&2
  exit 1
}

# --- Fixtures -----------------------------------------------------------------
# A small source tree, including a subdirectory and a symlink, so the round-trip
# check covers more than plain files.
src="${work}/important-stuff"
mkdir -p "${src}/sub"
echo "hello" >"${src}/a.txt"
echo "nested" >"${src}/sub/b.txt"
ln -s a.txt "${src}/link"

# Local rclone remote: type=local means remote paths are just filesystem paths,
# so TARCLONE_REMOTE_PATH points at a scratch directory and no backend is contacted.
dest="${work}/remote"
mkdir -p "$dest"
conf="${work}/rclone.conf"
printf '[teststore]\ntype = local\n' >"$conf"

export TARCLONE_SOURCE="$src"
export TARCLONE_REMOTE="teststore"
export TARCLONE_REMOTE_PATH="$dest"
export RCLONE_CONFIG="$conf"
export TARCLONE_STAGING_DIR="${work}/staging"
export TARCLONE_RETENTION_COUNT=2
export TARCLONE_VERIFY_CHECKSUM=true

shopt -s nullglob

# Run tarclone either directly (host mode) or inside the image (image mode). The
# whole fixture tree lives under $work, bind-mounted at the same path, so the
# absolute paths in the exported config resolve identically inside the container.
# --user matches the host so the non-root image can read/write the mount, and
# --network none proves the local-backend path needs no network.
run_tarclone() {
  if [[ -z "$image" ]]; then
    "$tarclone" "$@"
    return
  fi
  docker run --rm \
    --entrypoint /usr/local/bin/tarclone \
    --user "$(id -u):$(id -g)" \
    --network none \
    -e HOME="$work" \
    -e TARCLONE_SOURCE -e TARCLONE_REMOTE -e TARCLONE_REMOTE_PATH -e RCLONE_CONFIG \
    -e TARCLONE_STAGING_DIR -e TARCLONE_RETENTION_COUNT -e TARCLONE_VERIFY_CHECKSUM \
    -e TARCLONE_PING_URL="${TARCLONE_PING_URL:-}" \
    -e TARCLONE_PING_URL_FILE="${TARCLONE_PING_URL_FILE:-}" \
    -v "$work:$work" \
    "$image" "$@"
}

# --- 1. Introspection flags succeed and report the resolved config ------------
run_tarclone --check >/dev/null || fail "--check exited non-zero"
run_tarclone --show-config >/dev/null || fail "--show-config exited non-zero"
# A directly-set ping URL is the operator's choice to put in the environment, so
# --show-config prints it verbatim (it is tarclone's `env`). Capture the dump
# before grepping: piping into `grep -q` closes the pipe on first match, which
# SIGPIPEs the still-writing producer and, under pipefail, spuriously fails.
url_dump="$(TARCLONE_PING_URL="https://example.test/ping-token" run_tarclone --show-config)"
grep -q ping-token <<<"$url_dump" ||
  fail "--show-config did not report the configured ping URL"
# A ping URL supplied via *_FILE must be reported as its path, never resolved —
# the secret contents must not leak into the dump.
secret_file="${work}/ping-secret"
printf 'https://example.test/secret-from-file' >"$secret_file"
file_dump="$(TARCLONE_PING_URL_FILE="$secret_file" run_tarclone --show-config)"
grep -q secret-from-file <<<"$file_dump" &&
  fail "--show-config resolved a *_FILE secret into the dump"
grep -qF "TARCLONE_PING_URL_FILE=${secret_file}" <<<"$file_dump" ||
  fail "--show-config did not report the *_FILE path"

# --- 2. A run publishes exactly one archive that round-trips -------------------
run_tarclone || fail "backup run exited non-zero"
archives=("$dest"/important-stuff_*.tar.gz)
((${#archives[@]} == 1)) || fail "expected 1 published archive, found ${#archives[@]}"

restore="${work}/restore"
mkdir -p "$restore"
tar -xzf "${archives[0]}" -C "$restore"
diff -r "$src" "${restore}/important-stuff" || fail "restored tree differs from source"

# No .partial should linger after a successful publish.
leftovers=("$dest"/*.partial)
((${#leftovers[@]} == 0)) || fail "left a .partial behind: ${leftovers[*]}"

# --- 3. Retention caps the archive count --------------------------------------
# The timestamp has one-second resolution, so pause to guarantee distinct names.
for i in 1 2; do
  sleep 1.1
  run_tarclone || fail "backup run exited non-zero (retention loop ${i})"
done
archives=("$dest"/important-stuff_*.tar.gz)
((${#archives[@]} == TARCLONE_RETENTION_COUNT)) ||
  fail "retention: expected ${TARCLONE_RETENTION_COUNT} archives, found ${#archives[@]}"

echo "SMOKE OK"
