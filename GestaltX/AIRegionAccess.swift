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
                // This fork accepts one App Group only. In contrast to upstream,
                // do not enumerate or probe groups belonging to other apps.
                let group = "group.com.gobiologycn.gestaltxai"
                guard let root = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group
                ) else {
                    throw AIRegionError.denied("The signed app must contain the GestaltX-AI App Group.")
                }
                var handle = worse_query(target, group, false, false)
                if handle == -4 {
                    try? FileManager.default.createDirectory(
                        at: root.appendingPathComponent("Library/Caches"),
                        withIntermediateDirectories: true
                    )
                    handle = worse_query(target, group, false, false)
                }
                guard handle >= 0 else {
                    throw AIRegionError.denied("MobileGestalt sandbox extension could not be obtained.")
                }
                return handle
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
            message = "RegionCode verified as LL. Apple Intelligence availability is not guaranteed; a restart may be needed."
            return newState
        }
    }
    func restore() {
        run {
            let newState = try store.restore()
            needsRestart = true
            message = "Original CH RegionCode restored and verified; a restart may be needed."
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
