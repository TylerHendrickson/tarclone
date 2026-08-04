# Changelog

## [0.3.0](https://github.com/TylerHendrickson/tarclone/compare/v0.2.1...v0.3.0) (2026-08-04)


### Features

* verify uploads with `rclone check` ([#30](https://github.com/TylerHendrickson/tarclone/issues/30)) ([415b064](https://github.com/TylerHendrickson/tarclone/commit/415b064cd46566b5fe5057b550d1075175486f99))

## [0.2.1](https://github.com/TylerHendrickson/tarclone/compare/v0.2.0...v0.2.1) (2026-07-25)


### Bug Fixes

* cleanup fails when destination contains subdirectories ([#25](https://github.com/TylerHendrickson/tarclone/issues/25)) ([5b315b5](https://github.com/TylerHendrickson/tarclone/commit/5b315b59cfbc760b0fcb18483467202af21646a5))

## [0.2.0](https://github.com/TylerHendrickson/tarclone/compare/v0.1.0...v0.2.0) (2026-07-25)


### ⚠ BREAKING CHANGES

* the supercronic crontab path moved from /etc/backup/crontab to /etc/tarclone/crontab. Update your bind mount (compose `volumes:` or `docker run -v ...`) to target the new path.

### Features

* add input validation for config ([#20](https://github.com/TylerHendrickson/tarclone/issues/20)) ([972de45](https://github.com/TylerHendrickson/tarclone/commit/972de450d1faf099030bd52e8b6592f959d9cc61))
* move container crontab to /etc/tarclone/crontab ([364177b](https://github.com/TylerHendrickson/tarclone/commit/364177b9cf37f2e43dc050735bf0534c92b74d33))

## 0.1.0 (2026-07-24)


### Features

* add `--version` flag and `release-please` automation ([#16](https://github.com/TylerHendrickson/tarclone/issues/16)) ([c912efe](https://github.com/TylerHendrickson/tarclone/commit/c912efe41d1f81242b3089754cf8c298b226df3f))
* initial implementation ([#1](https://github.com/TylerHendrickson/tarclone/issues/1)) ([a8ead15](https://github.com/TylerHendrickson/tarclone/commit/a8ead153e844189505e44842320da392cd3b105c))


### Bug Fixes

* builds on main fail to upload attestation artifacts ([#15](https://github.com/TylerHendrickson/tarclone/issues/15)) ([43d6d86](https://github.com/TylerHendrickson/tarclone/commit/43d6d8681ad0c6d55e272c43a75b235fa8986d92))
* drop AnimMouse/setup-rclone in favor of direct download ([#18](https://github.com/TylerHendrickson/tarclone/issues/18)) ([d8f2ac6](https://github.com/TylerHendrickson/tarclone/commit/d8f2ac6f6d62b80ee17517660c558d9f217f777f))
* explicit config/manifest locations in release-please ([70abdb6](https://github.com/TylerHendrickson/tarclone/commit/70abdb6be11a81000b3042f1e20ec3e0cc1d36a3))
* flaky introspection smoke test ([#13](https://github.com/TylerHendrickson/tarclone/issues/13)) ([e734169](https://github.com/TylerHendrickson/tarclone/commit/e73416991e33d6305093375821cb6d7677b79a59))
* missing `release-please-config.json` ([a5eedce](https://github.com/TylerHendrickson/tarclone/commit/a5eedce5d12a698e92113682291ebfc080ee50a8))

## Changelog

All notable changes to this project are documented here. This file is maintained
automatically by [release-please](https://github.com/googleapis/release-please)
from [Conventional Commits](https://www.conventionalcommits.org/); the same notes
appear on each [GitHub Release](https://github.com/TylerHendrickson/tarclone/releases).
