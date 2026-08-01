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
    -e TARCLONE_ARCHIVE_PREFIX \
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

# --- 4. Foreign files and subdirectories in the destination are left alone -----
# Regression: a subdirectory in the destination once made the orphaned-.partial
# cleanup try to `deletefile` it, which aborted an already-published backup. More
# generally, tarclone must only ever delete objects it could itself have created
# (<prefix>_<timestamp>.tar.gz, optionally .partial), matched literally — never a
# subdirectory, an unrelated file, or a look-alike that shares our prefix but has
# no real timestamp. Such objects must be ignored by both cleanup and retention:
# never counted, never removed.
mkdir -p "$dest/keep/nested"
echo "important" >"$dest/keep/nested/note.txt"
echo "unrelated" >"$dest/unrelated.txt"
echo "other app's backup" >"$dest/otherapp_backup.tar.gz"
# Shares our prefix but is not a real archive; the eight zeros are not the
# YYYY-MM-DD_HHMMSS shape, and sort before real timestamps so a regression that
# counted or pruned foreign files would try to delete this one first.
echo "not a real archive" >"$dest/important-stuff_00000000.tar.gz"
echo "not a real partial" >"$dest/important-stuff_notatimestamp.tar.gz.partial"
# A genuinely orphaned partial (our exact naming) must still be reaped, so the
# hardened cleanup isn't silently over-tightened into doing nothing.
real_orphan="$dest/important-stuff_2020-01-01_000000.tar.gz.partial"
echo "orphaned" >"$real_orphan"

sleep 1.1
run_tarclone || fail "backup run failed with foreign files/subdirs in the destination"

[[ -d "$dest/keep/nested" && -f "$dest/keep/nested/note.txt" ]] ||
  fail "cleanup disturbed an unrelated subdirectory"
for decoy in unrelated.txt otherapp_backup.tar.gz important-stuff_00000000.tar.gz \
  important-stuff_notatimestamp.tar.gz.partial; do
  [[ -e "$dest/$decoy" ]] || fail "deleted a foreign file it did not create: ${decoy}"
done
[[ -e "$real_orphan" ]] && fail "a genuinely orphaned .partial was not cleaned up"
# Retention counts only real archives, so the look-alike above must not perturb it.
real_count=0
for f in "$dest"/important-stuff_*.tar.gz; do
  base="$(basename -- "$f")"
  [[ "$base" =~ ^important-stuff_[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])_([01][0-9]|2[0-3])[0-5][0-9]([0-5][0-9]|60)\.tar\.gz$ ]] &&
    real_count=$((real_count + 1))
done
((real_count == TARCLONE_RETENTION_COUNT)) ||
  fail "retention miscounted with foreign files present: found ${real_count}"

# --- 5. A prefix containing glob metacharacters is handled literally -----------
# The prefix is operator-configurable and may legally contain glob metacharacters.
# Every use of it must be literal, never a pattern — otherwise selecting what to
# delete could match, and remove, an unrelated file.
meta_dest="${work}/remote-meta"
mkdir -p "$meta_dest"
# If "app[1]" were ever expanded as a glob, its [1] class would match "app1_...",
# so this decoy must survive untouched.
decoy="${meta_dest}/app1_2020-01-01_000000.tar.gz"
echo "decoy" >"$decoy"

export TARCLONE_ARCHIVE_PREFIX='app[1]'
export TARCLONE_REMOTE_PATH="$meta_dest"
# Three runs against retention=2 so pruning actually deletes with this prefix.
for i in 1 2 3; do
  sleep 1.1
  run_tarclone || fail "backup run failed with a metacharacter prefix (run ${i})"
done

# Retention keeps exactly N, selected by the literal prefix (the test's own glob
# single-quotes [1] so it, too, matches literally rather than as a class).
metas=("$meta_dest"/'app[1]'_*.tar.gz)
((${#metas[@]} == TARCLONE_RETENTION_COUNT)) ||
  fail "metachar prefix: expected ${TARCLONE_RETENTION_COUNT} archives, found ${#metas[@]}"
[[ -e "$decoy" ]] || fail "metachar prefix matched as a glob and deleted the app1_* decoy"

# --- 6. Verification falls back to a download when the backend has no hash ------
# A crypt remote exposes no hash, so the no-download check can only compare sizes
# — which passes even on same-length corruption. tarclone must notice that and
# read the object back to compare bytes before publishing. Layer a crypt remote
# over the local store and assert a clean run publishes AND took the download path.
# The password is only ever revealed by the same config that obscured it, so any
# valid obscured value works; this one reveals to a throwaway test passphrase.
crypt_enc="${work}/remote-crypt-enc"
mkdir -p "$crypt_enc"
{
  printf '\n[cryptstore]\n'
  printf 'type = crypt\n'
  printf 'remote = teststore:%s\n' "$crypt_enc"
  printf 'password = A4qrsfrfesw-q35KaVC6HCaLa-qRC3Sj9IISYKhQ1Yoo4rgKow\n'
} >>"$conf"

export TARCLONE_ARCHIVE_PREFIX=crypt
export TARCLONE_REMOTE=cryptstore
export TARCLONE_REMOTE_PATH=
export TARCLONE_STAGING_DIR="${work}/staging-crypt"
crypt_log="${work}/crypt-run.log"
run_tarclone >"$crypt_log" 2>&1 || { cat "$crypt_log" >&2; fail "backup run failed against a crypt remote"; }
grep -q "verifying by download" "$crypt_log" ||
  fail "crypt remote did not fall back to download verification"
crypts=("$crypt_enc"/*)
((${#crypts[@]} >= 1)) || fail "crypt remote published nothing"

# --- End of tests (everything passed) ------------------------------------------
echo "SMOKE OK"
