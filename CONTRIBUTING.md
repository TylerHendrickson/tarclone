# Contributing

Thanks for your interest in tarclone!

## Ground rules

- **Conventional, not clever.** Prefer boring, idiomatic solutions.
- **Fail loud.** The script runs under `set -euo pipefail`; validate inputs early
  and exit non-zero on misconfiguration rather than limping on.
- **Don't reimplement platform mechanisms.** Lean on the shell, rclone, tar,
  supercronic, and Docker instead of re-creating what they already do.
- **Config is environment-driven.** Every knob is a `TARCLONE_*` variable with a
  default. If you add one, document it in [`example/tarclone.env`](example/tarclone.env)
  and include it in `--show-config`.

## Before you open a PR

Run both of these from the repo root; CI runs the same checks and fails on any finding:

```sh
shellcheck tarclone test/smoke.sh
./test/smoke.sh
```

To exercise a built image instead of the host script:

```sh
docker build --target base .
TARCLONE_IMAGE=<built-ref> ./test/smoke.sh
```

Please keep commits focused and use [Conventional Commits](https://www.conventionalcommits.org/),
as the [release tooling](https://github.com/googleapis/release-please) and history rely on it.

## Reporting bugs and requesting features

Open a GitHub issue with enough detail to reproduce: the version or image digest,
the relevant `TARCLONE_*` configuration (redact secrets), and what you observed
versus expected.

## Security

Please **do not** open a public issue for security vulnerabilities.
See [SECURITY.md](SECURITY.md) for private reporting instructions.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
