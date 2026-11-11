// SPDX-License-Identifier: GPL-3.0-only
// Derived from huamidev/GestaltX. Copyright belongs to its contributors.
import Foundation
import CryptoKit
import CoreFoundation

enum AIRegionError: LocalizedError {
    case denied(String)
    var errorDescription: String? {
        switch self { case .denied(let message): return message }
    }
}

enum AIRegionKeys {
    static let region = "h63QSdBCiT/z0WU6rdQv6Q"
    static let devicePath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let identity = [
        "UniqueDeviceID", "re6Zb+zwFKJNlkQTUeT+/w",
        "SerialNumber", "VasUgeSzVyHdB27g2XpN0g",
        "UniqueChipID", "TF31PAB6aO8KAbPyNKSxKA"
    ]
}

/// Property-list comparison checks nested types and values. NSNumber Bool(1)
/// and Int(1) must never compare equal merely because their numbers match.
enum AIPlist {
    static func equal(_ left: Any, _ right: Any) -> Bool {
        if let a = left as? [String: Any], let b = right as? [String: Any] {
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in
                b[key].map { equal(value, $0) } ?? false
            }
        }
        if let a = left as? [Any], let b = right as? [Any] {
            return a.count == b.count && zip(a, b).allSatisfy { equal($0.0, $0.1) }
        }
        if let a = left as? Data, let b = right as? Data { return a == b }
        if let a = left as? Date, let b = right as? Date { return a == b }
        if let a = left as? String, let b = right as? String { return a == b }
        if let a = left as? NSNumber, let b = right as? NSNumber {
            guard CFGetTypeID(a) == CFGetTypeID(b) else { return false }
            if CFGetTypeID(a) == CFBooleanGetTypeID() { return a.boolValue == b.boolValue }
            guard String(cString: a.objCType) == String(cString: b.objCType) else { return false }
            return a == b
        }
        return false
    }

    static func parse(_ bytes: Data) throws -> [String: Any] {
        guard let root = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any],
              root["CacheExtra"] is [String: Any] else {
            throw AIRegionError.denied("Invalid MobileGestalt plist: CacheExtra is missing.")
        }
        return root
    }

    static func encode(_ root: [String: Any]) throws -> Data {
        guard PropertyListSerialization.propertyList(root, isValidFor: .binary) else {
            throw AIRegionError.denied("The changed cache is not a valid property list.")
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    static func region(_ root: [String: Any]) -> String? {
        (root["CacheExtra"] as? [String: Any])?[AIRegionKeys.region] as? String
    }

    static func replacingRegion(in root: [String: Any], with code: String) throws -> [String: Any] {
        guard !code.isEmpty, var extra = root["CacheExtra"] as? [String: Any] else {
            throw AIRegionError.denied("Missing region or CacheExtra.")
        }
        extra[AIRegionKeys.region] = code
        var updated = root
        updated["CacheExtra"] = extra
        return updated
    }

    /// A single approved region field is the only permitted plist delta.
    static func validate(original: [String: Any], edited: [String: Any], target: String) throws {
        let allowed = try replacingRegion(in: original, with: target)
        guard equal(allowed, edited) else {
            throw AIRegionError.denied("Unexpected change outside RegionCode; refusing the write.")
        }
    }

    static func sameGeneration(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        for key in ["CacheUUID", "CacheVersion"] {
            switch (a[key], b[key]) {
            case (nil, nil): break
            case (let x?, let y?) where equal(x, y): break
            default: return false
            }
        }
        let ac = a["CacheData"] as? Data
        let bc = b["CacheData"] as? Data
        guard ac != nil, ac?.count == bc?.count else { return false }
        for key in AIRegionKeys.identity {
            let aID = (a["CacheExtra"] as? [String: Any])?[key]
            let bID = (b["CacheExtra"] as? [String: Any])?[key]
            switch (aID, bID) {
            case (nil, nil): break
            case (let x?, let y?) where equal(x, y): break
            default: return false
            }
        }
        return true
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIRegionState {
    let current: String
    let original: String
    let canEnable: Bool
    let canRestore: Bool
}

private struct AIBackupMetadata: Codable {
    let sha256: String
    let length: Int
    let recordedAt: Date
}

final class AIRegionStore {
    private let deviceURL: URL
    private let backupFolder: URL
    private let acquire: () throws -> Int64
    private let release: (Int64) -> Void
    private let write: (Data, URL) throws -> Void
    private var observedBytes: Data?

    init(
        deviceURL: URL,
        backupFolder: URL,
        acquire: @escaping () throws -> Int64,
        release: @escaping (Int64) -> Void,
        write: @escaping (Data, URL) throws -> Void = { bytes, path in try bytes.write(to: path) }
    ) {
        self.deviceURL = deviceURL
        self.backupFolder = backupFolder
        self.acquire = acquire
        self.release = release
        self.write = write
    }

    private var originalURL: URL { backupFolder.appendingPathComponent("OriginalMobileGestalt.plist") }
    private var metadataURL: URL { backupFolder.appendingPathComponent("OriginalMetadata.json") }

    private func scoped<T>(_ body: () throws -> T) throws -> T {
        let token = try acquire()
        guard token >= 0 else { throw AIRegionError.denied("Device access was denied.") }
        defer { release(token) }
        return try body()
    }

    private func savedOriginal() throws -> (Data, [String: Any])? {
        let hasData = FileManager.default.fileExists(atPath: originalURL.path)
        let hasMetadata = FileManager.default.fileExists(atPath: metadataURL.path)
        guard hasData == hasMetadata else {
            throw AIRegionError.denied("Original snapshot is incomplete. Stop before making changes.")
        }
        guard hasData else { return nil }
        let bytes = try Data(contentsOf: originalURL)
        let meta = try JSONDecoder().decode(AIBackupMetadata.self, from: Data(contentsOf: metadataURL))
        guard bytes.count == meta.length, AIPlist.hash(bytes) == meta.sha256 else {
            throw AIRegionError.denied("Original snapshot checksum mismatch. No change was made.")
        }
        return (bytes, try AIPlist.parse(bytes))
    }

    private func persist(_ bytes: Data, at path: URL) throws {
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        try bytes.write(to: path, options: .atomic)
        guard try Data(contentsOf: path) == bytes else {
            throw AIRegionError.denied("Backup verification failed. Device unchanged.")
        }
    }

    private func baseline(for bytes: Data, root: [String: Any]) throws -> [String: Any] {
        if let saved = try savedOriginal() {
            guard AIPlist.sameGeneration(saved.1, root) else {
                throw AIRegionError.denied("Device or cache generation differs from original backup. No write permitted.")
            }
            return saved.1
        }

        // Avoid creating a pretend factory backup when this app first sees a
        // device whose region code is already modified.
        guard AIPlist.region(root) == "CH" else {
            throw AIRegionError.denied("No original backup exists and RegionCode is not CH; refusing to infer an original value.")
        }
        let metadata = AIBackupMetadata(sha256: AIPlist.hash(bytes), length: bytes.count, recordedAt: .now)
        persist(bytes, at: originalURL)
        persist(try JSONEncoder().encode(metadata), at: metadataURL)
        return root
    }

    private func readSnapshot() throws -> (Data, [String: Any]) {
        let bytes = try Data(contentsOf: deviceURL)
        guard bytes.count <= 16 * 1024 * 1024 else {
            throw AIRegionError.denied("Unexpectedly large MobileGestalt cache.")
        }
        return (bytes, try AIPlist.parse(bytes))
    }

    func inspect() throws -> AIRegionState {
        try scoped {
            let (bytes, root) = try readSnapshot()
            let original = try baseline(for: bytes, root: root)
            observedBytes = bytes
            let current = AIPlist.region(root) ?? "Unknown"
            let prior = AIPlist.region(original) ?? "Unknown"
            return AIRegionState(
                current: current,
                original: prior,
                canEnable: current == "CH" && prior == "CH",
                canRestore: current == "LL" && prior == "CH"
            )
        }
    }

    func enable() throws -> AIRegionState { try change(to: "LL") }

    func restore() throws -> AIRegionState {
        let original = try savedOriginal()
        guard let original, AIPlist.region(original.1) == "CH" else {
            throw AIRegionError.denied("A verified original CH-region backup is required to restore.")
        }
        return try change(to: "CH")
    }

    private func change(to target: String) throws -> AIRegionState {
        guard target == "LL" || target == "CH" else {
            throw AIRegionError.denied("Only the US region and original China region are allowed.")
        }
        return try scoped {
            let (before, root) = try readSnapshot()
            guard observedBytes == before else {
                throw AIRegionError.denied("The device cache changed since inspection. Read it again.")
            }
            let original = try baseline(for: before, root: root)
            let originalCode = AIPlist.region(original)
            let currentCode = AIPlist.region(root)
            guard originalCode == "CH",
                  (target == "LL" && currentCode == "CH") || (target == "CH" && currentCode == "LL") else {
                throw AIRegionError.denied("Unexpected region state. No change made.")
            }
            let edited = try AIPlist.replacingRegion(in: root, with: target)
            try AIPlist.validate(original: root, edited: edited, target: target)
            let next = try AIPlist.encode(edited)
            // The up-to-date cache is backed up *before each individual write*,
            // not just on first launch, so failures can be recovered from bytes.
            let backupPath = backupFolder.appendingPathComponent("BeforeWrite-\(UUID().uuidString).plist")
            persist(before, at: backupPath)
            guard Data(contentsOf: deviceURL) == before else {
                throw AIRegionError.denied("Device changed after backup. No write made.")
            }
            do {
                try write(next, deviceURL)
                let readback = try readSnapshot()
                guard AIPlist.equal(readback.1, edited) else {
                    throw AIRegionError.denied("Write verification mismatch.")
                }
                observedBytes = readback.0
            } catch {
                do {
                    try write(before, deviceURL)
                    guard try Data(contentsOf: deviceURL) == before else {
                        throw AIRegionError.denied("Rollback verification failed.")
                    }
                } catch {
                    throw AIRegionError.denied("CRITICAL: write/rollback failed. Do not retry or restart; preserve backup and seek recovery.")
                }
                throw AIRegionError.denied("Write failed; previous cache bytes restored and verified.")
            }
            return AIRegionState(
                current: target, original: "CH",
                canEnable: target == "CH", canRestore: target == "LL"
            )
        }
    }
}
