# GestaltX-AI — inspection prototype (Phase 1)

This is a limited, **read-only user-interface prototype** derived from [huamidev/GestaltX](https://github.com/huamidev/GestaltX), not a security-reviewed Apple Intelligence unlock.

## Purpose

- Read the device's existing MobileGestalt cache on supported iOS 27.x systems.
- Display the existing `RegionCode` value and the **proposed** US value (`LL`).
- Create a device-cache backup in the app container using the upstream backup implementation.
- **Do not apply any change to the iPhone.** There are deliberately no Apply, Restore, model-spoofing or eSIM controls in the new entry screen.

## Scope and honest limitations

The inherited codebase still contains generic field editing, other capability presets, full-plist restoration and a share extension. This initial commit changes **the launched screen**, not the reachability of all underlying routines. It is **not yet** a field-level whitelist or a minimal attack surface.

Read/backup operations use upstream `worse_query`, a sandbox escape. A read-only UI does not remove that risk. It may affect the app's temporary container state. This code has not been audited for security, built with Xcode, or verified on a physical iPhone in this development session.

The app-container backup is not a full-device backup and could be lost on app deletion. Do not rely on it as the sole recovery method. Apple Intelligence availability may still be limited by hardware, iOS version, and Apple server-side restrictions.

## Phase 2 progress (source code only)

A strict policy has been added to `GestaltFileStore.commit`, the final device-write entry point. For normal device writes the target is strictly `CacheExtra[RegionCode] = "LL"`; for a verified backup restore the only permissible difference is the saved region value, and all unrelated plist content (including sales-region fields and `CacheData`) must remain equivalent to the current device snapshot. This is a defense-in-depth preflight, **not** a guarantee against bugs or the underlying sandbox-escape risk.

Fixture scenarios were authored in `tests/AIRegionWritePolicyTests.swift` for allowed US code, unrelated-field rejection, type rejection, CacheData mutation rejection, backups, and region-only restoration. **These tests have not yet been executed**, and existing legacy tests expecting unrestricted edits will need migration before they can be used as regression checks. The physical device is **not** connected or modified.

The entry screen is still inspection-only. The underlying general-purpose code and share extension remain compiled and have **not** been deleted. No installable binary has been verified.

## Proposed Phase 2 acceptance criteria

1. Remove unrelated features, share extension, imports, generic editor, and unused dependencies from the build rather than merely hiding them.
2. ~~Enforce a write-time allowlist~~ **Implemented in source; awaiting compilation and fixture test results.** Only the region-code field may change even during restore; arbitrary whole-file restoration is not permitted.
3. Preserve and test upstream backup creation, data integrity verification, readback verification, failure recovery, and device-identity checks.
4. Require explicit review of original and proposed values before any write.
5. Test on synthetic fixtures and a supported non-primary test device before exposing write controls.
6. Review licensing and third-party notices; retain upstream attribution and GPL-3.0-only terms.

## Original project and license

Upstream: https://github.com/huamidev/GestaltX

Copyright remains with original contributors. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
