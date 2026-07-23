# Security Policy

## Reporting a Vulnerability

Please report suspected vulnerabilities **privately** rather than opening a
public issue. Use GitHub's [private vulnerability reporting][report] ("Report a
vulnerability" under the repository's **Security** tab), which opens a
confidential advisory visible only to the maintainer.

Include enough detail to reproduce: the affected version or image digest, the
relevant configuration, and the impact you observed. Reports are acknowledged on
a best-effort basis, and a fix and coordinated disclosure will be worked out with
you.

[report]: https://github.com/TylerHendrickson/tarclone/security/advisories/new

## Supported Versions

tarclone is released from `main`; security fixes land there and in the most
recent tagged release. Older tags are not backported — pin to a recent version
and update when fixes ship.

## Scope

In scope: the `tarclone` script and the published container images
(`ghcr.io/tylerhendrickson/tarclone`). Vulnerabilities in the bundled upstream
tools (rclone, supercronic, the base image) are addressed by rebuilding against
patched versions rather than by patching them here.

## Supply chain

Published images are scanned for known vulnerabilities (Trivy) on every change,
and each carries a signed SLSA build provenance attestation and an SPDX SBOM.
See [Verifying images](README.md#verifying-images) to check them.
