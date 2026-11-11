// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

enum AIRegionAccess {
    static var supported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27
    }

    static func makeStore() -> AIRegionStore {
        let home = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("GestaltX-AI", isDirectory: true)

        return AIRegionStore(
            deviceURL: URL(fileURLWithPath: AIRegionKeys.devicePath),
            backupFolder: home,
            acquire: {
                #if targetEnvironment(simulator)
                throw AIRegionError.denied("MobileGestalt access requires a supported physical iPhone.")
                #else
                guard supported else {
                    throw AIRegionError.denied("Only iOS 27.x is supported by this exploit.")
                }
                let target = (AIRegionKeys.devicePath as NSString).deletingLastPathComponent
                let signedGroups = GXEntitlementsReader.usableAppGroups()
                guard !signedGroups.isEmpty else {
                    throw AIRegionError.denied("The signed app needs a usable App Group entitlement.")
                }
                for signedGroup in signedGroups {
                    var handle = worse_query(target, signedGroup, false, false)
                    if handle == -4,
                       let root = FileManager.default.containerURL(
                        forSecurityApplicationGroupIdentifier: signedGroup
                       ) {
                        // Preserve the existing upstream container setup path.
                        try? FileManager.default.createDirectory(
                            at: root.appendingPathComponent("Library/Caches"),
                            withIntermediateDirectories: true
                        )
                        handle = worse_query(target, signedGroup, false, false)
                    }
                    if handle >= 0 { return handle }
                }
                throw AIRegionError.denied("MobileGestalt sandbox extension could not be obtained.")
                #endif
            },
            release: { worse_query_release($0) }
        )
    }
}

@MainActor
final class AIRegionManager: ObservableObject {
    @Published private(set) var state: AIRegionState?
    @Published private(set) var busy = false
    @Published private(set) var needsRestart = false
    @Published var message: String?
    private let store = AIRegionAccess.makeStore()

    func inspect() {
        run { try store.inspect() }
    }
    func enable() {
        run {
            let newState = try store.enable()
            needsRestart = true
            return newState
        }
    }
    func restore() {
        run {
            let newState = try store.restore()
            needsRestart = true
            return newState
        }
    }

    private func run(_ action: () throws -> AIRegionState) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { state = try action() }
        catch {
            // Discard stale state on failure to make users read again.
            state = nil
            message = error.localizedDescription
        }
    }
}
