// SPDX-License-Identifier: GPL-3.0-only
// This standalone fixture test does not use a real device or sandbox escape.
import Foundation

@main
struct AIRegionWritePolicyTests {
    struct Failure: Error { let message: String }

    static func require(_ passed: Bool, _ message: String) throws {
        if !passed { throw Failure(message: message) }
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch is GestaltFailure {
            return
        }
        throw Failure(message: message)
    }

    static func main() async throws {
        let region = GestaltKeys.regionCode
        let originalRoot: [String: Any] = [
            "CacheUUID": "fixture-generation",
            "CacheVersion": "fixture-version",
            "CacheData": Data([0, 1, 2, 3]),
            "CacheExtra": [
                region: "CH",
                GestaltKeys.regionInfo: "CH/A",
                GestaltKeys.modelNumber: "test-model",
                "unrelatedField": NSNumber(value: true)
            ] as [String: Any]
        ]
        let originalBytes = try PropertyListSerialization.data(
            fromPropertyList: originalRoot, format: .binary, options: 0
        )
        let original = try GestaltDocument(data: originalBytes)
        var usOnly = original
        usOnly.set("LL", for: region)
        try AIRegionWritePolicy.validate(original: original, edited: usOnly, restoring: false)

        let noChange = original
        try rejects("Ordinary write accepted a target other than LL") {
            try AIRegionWritePolicy.validate(original: original, edited: noChange, restoring: false)
        }

        for (field, value) in [
            (GestaltKeys.regionInfo, "LL/A"),
            (GestaltKeys.modelNumber, "spoof-model"),
            ("unrelatedField", "unexpected")
        ] {
            var changed = usOnly
            changed.set(value, for: field)
            try rejects("Unrelated field was accepted: " + field) {
                try AIRegionWritePolicy.validate(original: original, edited: changed, restoring: false)
            }
        }

        var invalidType = original
        invalidType.set(NSNumber(value: 1), for: region)
        try rejects("Non-string RegionCode accepted") {
            try AIRegionWritePolicy.validate(original: original, edited: invalidType, restoring: true)
        }

        var changedRoot = originalRoot
        changedRoot["CacheData"] = Data([0, 1, 2, 4])
        var invalidCache = try GestaltDocument(data: PropertyListSerialization.data(
            fromPropertyList: changedRoot, format: .binary, options: 0
        ))
        invalidCache.set("LL", for: region)
        try rejects("A CacheData change was accepted") {
            try AIRegionWritePolicy.validate(original: original, edited: invalidCache, restoring: false)
        }

        // A validated region-only restore may return to the saved original code.
        try AIRegionWritePolicy.validate(original: usOnly, edited: original, restoring: true)

        // Integration: rejected writes must not acquire an extension or alter bytes.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let deviceURL = temporary.appendingPathComponent("device.plist")
        let backupsURL = temporary.appendingPathComponent("backups")
        try originalBytes.write(to: deviceURL)
        let store = GestaltFileStore(
            deviceURL: deviceURL, backupDirectory: backupsURL, deviceID: "ai-only-fixture",
            acquire: { 1 }, release: { _ in }
        )
        let loaded = try await store.loadDevice()
        var wrongEdit = loaded.document
        wrongEdit.set("LL", for: region)
        wrongEdit.set("LL/A", for: GestaltKeys.regionInfo)
        do {
            _ = try await store.commit(wrongEdit, expected: loaded)
            throw Failure(message: "Device writer accepted Sales Region modification")
        } catch is GestaltFailure {}
        try require(try Data(contentsOf: deviceURL) == originalBytes,
                    "Rejected edit modified the fixture device")

        var allowedEdit = loaded.document
        allowedEdit.set("LL", for: region)
        let applied = try await store.commit(allowedEdit, expected: loaded)
        try require(applied.document.extra[region] as? String == "LL",
                    "Allowed region-only update did not round-trip")
        try require(applied.document.extra[GestaltKeys.regionInfo] as? String == "CH/A",
                    "Allowed region-only update changed Sales Region")

        let originalBackup = try await store.backups().first(where: { $0.reason == "Initial backup" })
        try require(originalBackup != nil, "Original cache backup missing")
        if let originalBackup {
            let restored = try await store.commit(original, expected: applied, restoring: originalBackup)
            try require(restored.document.matches(original), "Verified backup region restore did not round-trip")
        }
        print("PASS: AI-only region allowlist, unrelated fields and cache rejection, backup, write and restore fixtures.")
    }
}
