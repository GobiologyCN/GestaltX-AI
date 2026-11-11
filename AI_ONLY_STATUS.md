# GestaltX-AI status and safety notes

## Implemented in source

- One iOS app target; original Share Extension, document import, general MobileGestalt editor and unrelated capability presets deleted.
- Strict `RegionCode` edit restricted to CH → LL and validated original LL → CH restore.
- Full-plist deep equality checks to reject unexpected fields, altered types and `CacheData` mutations.
- An immutable-once-created original snapshot and SHA-256 metadata, validated before updates or restoration.
- Pre-write snapshot, freshness check, readback validation, best-effort rollback if writing fails.
- Explicit UI confirmation, no auto-respring and no other optional feature controls.
- Synthetic fixture test suite for core behavior and recovery.

## Security limitations

- `worse_query` still uses a sandbox escape and touches its App Group temporary cache link. The original implementation has not undergone a formal security audit in this fork.
- The code is not yet proven safe on iOS 27.2.1. A successful compile/test does not prove a real device is safe or Apple's region limitation can be bypassed.
- Backups are stored in the app's Application Support folder; app deletion or device loss can remove them. A full encrypted iPhone backup is still essential before deployment.
- The implementation writes the existing protected cache file and attempts rollback, but a crash or storage failure between steps can still leave a corrupt cache. **Do not test on a primary iPhone without accepting this risk.**
- The app performs no server communication of its own, but upstream dependencies and Apple's iOS services are outside this statement.

## Verification gates

1. GitHub Actions synthetic fixture tests pass.
2. iPhone Simulator and iPhoneOS builds pass and the ad-hoc signature has only the expected App Group.
3. Code review of the resulting source diff and existing `worse_query` and `GXCacheDirectory` C/ObjC files.
4. Manually inspect signed entitlements after re-signing for the chosen install method.
5. Full encrypted iPhone backup and preferably non-primary test-device validation.
6. Physical test confirms CH → LL, no unrelated data change, and LL → CH restore.

**No actual iPhone verification has been performed in this development session.**

## License

Derived from [huamidev/GestaltX](https://github.com/huamidev/GestaltX). Copyright holders retain their rights; GPL-3.0-only applies. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
