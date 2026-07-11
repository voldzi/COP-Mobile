# Pinned COP Device contract

This directory is a read-only build input copied from the authoritative COP
repository. `contract.lock.json` pins the semantic version, source repository,
commit and package path. The mobile repository must never edit files under
`artifact/` by hand.

Refresh from a local COP checkout:

```bash
bash scripts/sync-cop-device-contract.sh \
  "/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/01 COP"
```

Verify that the checked-in artifact exactly matches the pinned commit:

```bash
bash scripts/sync-cop-device-contract.sh --check \
  "/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/01 COP"
```

Changing the lock requires an intentional contract review in the owning COP
repository first. Swift tests consume the shared fixture manifest from
`artifact/fixtures/v1/manifest.json`.
