# ADR 0007: Approved Xcode 27 toolchain

## Status

Accepted — 2026-07-11; updated — 2026-09-19

## Context

COP Mobile targets iOS/iPadOS 26. The original feasibility phase pinned an
Xcode 27 beta build. The maintained workstation now provides final Xcode 27.1
build `27A9269` and iOS SDK 27.1; the superseded beta build is no longer an
appropriate reproducible release baseline.

## Decision

- Pin builds and tests to Xcode 27.1 build `27A9269` and iOS SDK 27.1.
- Keep `IPHONEOS_DEPLOYMENT_TARGET=26.0`; SDK selection does not raise the
  minimum supported system.
- Enforce the exact pin with `scripts/verify-apple-toolchain.sh`.
- Run the GitHub iOS job only on a trusted ARM64 macOS self-hosted runner with
  the repository's `xcode-27-beta` compatibility label until the runner label
  is migrated independently.
- Never run repository `pull_request` code on that internal runner. Hosted Linux
  jobs continue to validate documentation and scan secrets for pull requests.
- Treat any Xcode 27 build upgrade as an explicit change: update this ADR,
  the verifier pin and the recorded simulator/device evidence together.

## Consequences

- Local and CI Swift/WebKit behavior use the same compiler and SDK build.
- CI requires runner registration and maintenance; until the labeled runner is
  online, the iOS job remains queued and is not acceptance evidence.
- Compiler/SDK regressions are an accepted project risk and must not be hidden
  by silently falling back to Xcode 26.
- App Store/TestFlight submission compatibility must be rechecked before each
  distribution.

## Approved update on 2026-10-04

The human explicitly approved the already installed Xcode 27.1 (27A9269),
iOS SDK27.1 in Jízda turn 01a10762-dadd-7b70-bc0e-f8ba8d5ecf80.
No download or deployment-target change is part of this approval. The exact
verifier remains mandatory; builds and tests must be rerun for this update.
