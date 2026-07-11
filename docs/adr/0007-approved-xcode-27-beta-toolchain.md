# ADR 0007: Approved Xcode 27 beta toolchain

## Status

Accepted — 2026-07-11

## Context

COP Mobile targets iOS/iPadOS 26. The product owner requires Xcode 27 beta for
development and validation. The current workstation provides Xcode 27.0 build
`27A5218g` and iOS SDK 27.0. GitHub-hosted macOS runner images do not currently
provide Xcode 27, so selecting an older hosted Xcode would violate the approved
toolchain decision.

## Decision

- Pin builds and tests to Xcode 27.0 build `27A5218g` and iOS SDK 27.0.
- Keep `IPHONEOS_DEPLOYMENT_TARGET=26.0`; SDK selection does not raise the
  minimum supported system.
- Enforce the exact pin with `scripts/verify-apple-toolchain.sh`.
- Run the GitHub iOS job only on a trusted ARM64 macOS self-hosted runner with
  label `xcode-27-beta`.
- Never run repository `pull_request` code on that internal runner. Hosted Linux
  jobs continue to validate documentation and scan secrets for pull requests.
- Treat any Xcode 27 beta build upgrade as an explicit change: update this ADR,
  the verifier pin and the recorded simulator/device evidence together.

## Consequences

- Local and CI Swift/WebKit behavior use the same compiler and SDK build.
- CI requires runner registration and maintenance; until the labeled runner is
  online, the iOS job remains queued and is not acceptance evidence.
- Beta compiler/SDK regressions are an accepted project risk and must not be
  hidden by silently falling back to Xcode 26.
- App Store/TestFlight submission compatibility must be rechecked before each
  distribution because beta toolchains can be rejected by Apple distribution
  services.
