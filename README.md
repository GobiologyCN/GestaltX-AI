# GestaltX-AI

**Minimal, unofficial and experimental** Apple Intelligence region-code tool for Chinese-market iPhones running supported iOS 27.x versions. Derived from [huamidev/GestaltX](https://github.com/huamidev/GestaltX); licensed under GPL-3.0-only.

This is a **narrow one-field editor**, not a jailbreak and **not a security-reviewed** App. It uses `worse_query` to escape iOS sandbox restrictions temporarily; unlike a normal app, that operation itself has security and stability risks.

## Exactly what the code does

- Reads the existing MobileGestalt system cache after requesting its sandbox extension.
- Saves and verifies an original, full-byte cache snapshot **only when the first region is CH**.
- Allows **CH → LL** by changing `CacheExtra[h63QSdBCiT/z0WU6rdQv6Q]` (`RegionCode`) and nothing else.
- Allows **LL → CH** only after verifying the original snapshot and cache generation; does not copy the old entire cache over the current system state.
- Backs up the current bytes before each write, checks the current file has not changed, verifies readback, and attempts to restore prior bytes if the write fails.
- Requires explicit confirmation for each change. Never resprings automatically.

It does **not** contain Dynamic Island tweaks, device-model spoofing, custom-field editing, sales-region modification, eSIM toggles, shared-file import or an extension.

## Restrictions and risks

- **Hardware:** a compatible iPhone (the intended test device is Chinese-market iPhone 15 Pro).
- **OS:** iOS 27.x; 27.2.1 is the intended user version, **not yet tested on an actual device**.
- **No guaranteed activation:** Apple's Apple Intelligence device-region restrictions and server-side checks can still prevent activation.
- **No guarantee of safe recovery:** writing the cache can disrupt iOS. An app-container cache snapshot is not a full-device backup. Back up the iPhone to an encrypted computer backup before attempting any physical write.
- **No network access added:** there are no user-authored networking clients or telemetry. The inherited `worse_query` implementation remains a privileged sandbox escape and needs separate security review.
- A re-signing tool must provision the app's isolated App Group `group.com.gobiologycn.gestaltxai` correctly. An ad-hoc signed IPA produced by CI is **not normally installable without re-signing**.

## Build and tests

The repository is an Xcode iOS app with a single target. GitHub Actions builds the iOS Simulator app, executes synthetic fixture tests, and packages an ad-hoc development IPA **only after those checks succeed**.

Locally on a Mac with Xcode:

```bash
swiftc -o /tmp/AIRegionCoreTests GestaltX/AIRegionCore.swift tests/AIRegionCoreTests.swift
/tmp/AIRegionCoreTests
xcodebuild -project GestaltX.xcodeproj -target GestaltX -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Please inspect [AI_ONLY_STATUS.md](AI_ONLY_STATUS.md) before physical testing.

Original authors and third-party software retain their copyright. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
