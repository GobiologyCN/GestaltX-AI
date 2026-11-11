// SPDX-License-Identifier: GPL-3.0-only
// Synthetic fixtures only; no iPhone, signing or sandbox escape required.
import Foundation

@main
struct AIRegionCoreTests {
    struct Failure: Error { let reason: String }

    static func check(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(reason: reason) }
    }
    static func rejected(_ reason: String, _ f: () throws -> Void) throws {
        do { try f() }
        catch is AIRegionError { return }
        throw Failure(reason: reason)
    }
    static func fixture(_ region: String = "CH") throws -> Data {
        let plist: [String: Any] = [
            "CacheUUID": "fixture-cache",
            "CacheVersion": "fixture-v1",
            "CacheData": Data([0, 1, 2, 3, 4]),
            "CacheExtra": [
                AIRegionKeys.region: region,
                "zHeENZu+wbg7PUprwNwBWg": "CH/A",
                "97JDvERpVwO+GHtthIh7hA": "iPhone15,2",
                "UniqueDeviceID": "fixture-device",
                "UnrelatedFlag": NSNumber(value: true)
            ] as [String: Any]
        ]
        return try AIPlist.encode(plist)
    }
    static func setup(_ bytes: Data) throws -> (URL, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("mobilegestalt.plist")
        try bytes.write(to: file)
        return (dir, file, dir.appendingPathComponent("backups"))
    }

    static func main() throws {
        let originalBytes = try fixture()
        let original = try AIPlist.parse(originalBytes)
        let modified = try AIPlist.replacingRegion(in: original, with: "LL")
        try AIPlist.validate(original: original, edited: modified, target: "LL")

        // A region-only edit cannot silently change any unrelated values.
        let regionInfo = "zHeENZu+wbg7PUprwNwBWg"
        for (key, value) in [
            (regionInfo, "LL/A"),
            ("UnrelatedFlag", "false"),
            ("97JDvERpVwO+GHtthIh7hA", "spoofed")
        ] {
            var changed = modified
            var extra = changed["CacheExtra"] as! [String: Any]
            extra[key] = value
            changed["CacheExtra"] = extra
            try rejected("An unrelated CacheExtra edit passed: " + key) {
                try AIPlist.validate(original: original, edited: changed, target: "LL")
            }
        }
        var modifiedCache = modified
        modifiedCache["CacheData"] = Data([0, 1, 2, 3, 5])
        try rejected("An unrelated CacheData edit passed") {
            try AIPlist.validate(original: original, edited: modifiedCache, target: "LL")
        }
        var boolReplaced = original
        var value = boolReplaced["CacheExtra"] as! [String: Any]
        value["UnrelatedFlag"] = NSNumber(value: 1)
        boolReplaced["CacheExtra"] = value
        try check(!AIPlist.equal(original, boolReplaced), "Bool and Int must not compare equal")

        // Full happy path: original snapshot, region-only write, verified
        // readback, and region-only restoration from the original snapshot.
        do {
            let (dir, file, backup) = try setup(originalBytes)
            defer { try? FileManager.default.removeItem(at: dir) }
            var acquisitions = 0, releases = 0
            let store = AIRegionStore(
                deviceURL: file, backupFolder: backup,
                acquire: { acquisitions += 1; return 7 },
                release: { _ in releases += 1 }
            )
            let initial = try store.inspect()
            try check(initial.current == "CH" && initial.canEnable, "Initial CH state")
            let enabled = try store.enable()
            try check(enabled.current == "LL" && enabled.canRestore, "US region write")
            let current = try AIPlist.parse(Data(contentsOf: file))
            try check(AIPlist.region(current) == "LL", "Written region")
            try check((current["CacheExtra"] as! [String: Any])[regionInfo] as? String == "CH/A", "Sales Region unchanged")
            _ = try store.inspect()
            let restored = try store.restore()
            try check(restored.current == "CH" && restored.canEnable, "Original region restored")
            try check(AIPlist.equal(try AIPlist.parse(Data(contentsOf: file)), original), "All original fields restored")
            try check(acquisitions == releases, "Sandbox handle release balanced")
        }

        // A stale read may never overwrite an independently changed cache.
        do {
            let (dir, file, backup) = try setup(originalBytes)
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = AIRegionStore(deviceURL: file, backupFolder: backup, acquire: { 7 }, release: { _ in })
            _ = try store.inspect()
            var tampered = try AIPlist.parse(originalBytes)
            tampered["CacheVersion"] = "externally-modified"
            try AIPlist.encode(tampered).write(to: file)
            try rejected("Stale snapshot was accepted") { _ = try store.enable() }
        }

        // Never invent the original CH state if the first read is already LL.
        do {
            let (dir, file, backup) = try setup(fixture("LL"))
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = AIRegionStore(deviceURL: file, backupFolder: backup, acquire: { 7 }, release: { _ in })
            try rejected("Already-modified first read was accepted") { _ = try store.inspect() }
        }

        // Corrupt the baseline: fail closed before attempting a system write.
        do {
            let (dir, file, backup) = try setup(originalBytes)
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = AIRegionStore(deviceURL: file, backupFolder: backup, acquire: { 7 }, release: { _ in })
            _ = try store.inspect()
            try Data([1, 2, 3]).write(to: backup.appendingPathComponent("OriginalMobileGestalt.plist"))
            try rejected("Corrupted original backup was accepted") { _ = try store.enable() }
            try check(try Data(contentsOf: file) == originalBytes, "Backup corruption must not touch device")
        }

        // A silent, invalid write is detected and rolls back to exact bytes.
        do {
            let (dir, file, backup) = try setup(originalBytes)
            defer { try? FileManager.default.removeItem(at: dir) }
            var writes = 0
            let store = AIRegionStore(
                deviceURL: file, backupFolder: backup, acquire: { 7 }, release: { _ in },
                write: { data, path in
                    writes += 1
                    if writes == 1 { try Data([0, 1]).write(to: path) }
                    else { try data.write(to: path) }
                }
            )
            _ = try store.inspect()
            try rejected("Unverified write reported success") { _ = try store.enable() }
            try check(writes == 2, "Failed write needs rollback attempt")
            try check(try Data(contentsOf: file) == originalBytes, "Rollback must restore exact previous bytes")
        }

        print("PASS: region-only policy, original backup, stale state, corruption, write verification and rollback.")
    }
}
