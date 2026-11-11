// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Only the Apple Intelligence region-code workflow is exposed.
/// No file import, generic editor, share extension, model spoofing or eSIM UI.
struct ContentView: View {
    @StateObject private var model = AIRegionManager()
    @State private var confirmEnable = false
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Model", value: UIDevice.current.model)
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    LabeledContent("Supported range", value: "iOS 27.x")
                    if !AIRegionAccess.supported {
                        Label("Unsupported iOS version. Device access is disabled.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    Button {
                        model.inspect()
                    } label: {
                        Label("Read device and verify original backup", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.busy || !AIRegionAccess.supported)
                    LabeledContent("Current RegionCode", value: model.state?.current ?? "Not read")
                    LabeledContent("Original RegionCode", value: model.state?.original ?? "Not verified")
                }

                Section("Apple Intelligence region") {
                    LabeledContent("Requested RegionCode", value: "LL (United States)")
                    Text("This changes only the MobileGestalt RegionCode field. Sales Region, model number, eSIM and all other capabilities remain unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        confirmEnable = true
                    } label: {
                        Label("Set RegionCode to LL", systemImage: "checkmark.shield")
                    }
                    .disabled(model.busy || model.state?.canEnable != true)

                    Button {
                        confirmRestore = true
                    } label: {
                        Label("Restore original RegionCode", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(model.busy || model.state?.canRestore != true)
                }

                Section("Important precautions") {
                    Label("A verified cache backup is required before any write.", systemImage: "externaldrive")
                    Label("Make a full encrypted iPhone backup separately.", systemImage: "lock.shield")
                    Label("Apple Intelligence activation is not guaranteed.", systemImage: "info.circle")
                    Label("Sandbox escape is still required; this is not a jailbreak.", systemImage: "exclamationmark.shield")
                    if model.needsRestart {
                        Label("A successful region change may require restarting the iPhone.", systemImage: "restart")
                            .foregroundStyle(.orange)
                    }
                    Text("If the device's original region is not CH, its cache generation changes, or saved backup verification fails, the application refuses all writes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GestaltX-AI")
            .toolbar {
                if model.busy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .alert("Change this iPhone's region code?", isPresented: $confirmEnable) {
                Button("Cancel", role: .cancel) {}
                Button("Set to LL", role: .destructive) { model.enable() }
            } message: {
                Text("Only RegionCode: CH → LL. The app will save the current cache, perform one verified write, and attempt rollback if verification fails. Apple Intelligence might still remain unavailable.")
            }
            .alert("Restore original region code?", isPresented: $confirmRestore) {
                Button("Cancel", role: .cancel) {}
                Button("Restore CH", role: .destructive) { model.restore() }
            } message: {
                Text("Only RegionCode: LL → CH, using the locally verified original snapshot. Sales Region and all other cache fields will remain unchanged.")
            }
            .alert("GestaltX-AI", isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )) {
                Button("OK", role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
        }
    }
}
