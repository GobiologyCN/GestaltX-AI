// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev and contributors
import SwiftUI

/// Phase 1: inspection and backup only. No device-write control is exposed.
/// The inherited MobileGestalt reader still uses worse_query and therefore
/// must not be treated as an ordinary sandboxed read.
struct AIOnlyPreviewView: View {
    @StateObject private var model = GestaltManager()

    private var currentRegionCode: String {
        guard model.sourceIsDevice,
              let value = model.snapshot?.document.extra[GestaltKeys.regionCode] as? String else {
            return "Not read"
        }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("iOS version", value: UIDevice.current.systemVersion)
                    LabeledContent("Supported range", value: VersionSupport.range)
                    LabeledContent("Connection", value: model.sourceIsDevice ? "Connected" : "Not connected")
                    LabeledContent("Current RegionCode", value: currentRegionCode)
                    Button {
                        Task { await model.connect() }
                    } label: {
                        Label("Read MobileGestalt", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy || !VersionSupport.current)
                    if !VersionSupport.current {
                        Text("The inherited reader does not support this iOS version.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Apple Intelligence — proposed change") {
                    LabeledContent("Field", value: "RegionCode")
                    LabeledContent("Proposed value", value: "LL")
                    Text("No Sales Region, device model, eSIM, or other capability flag is staged or changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Backup") {
                    Button {
                        Task { await model.backup() }
                    } label: {
                        Label("Create local device backup", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(!model.sourceIsDevice || model.isBusy)
                    Text("This saves a backup inside the app container; it does not back up the entire iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Safety status") {
                    Label("Inspection-only prototype", systemImage: "lock.shield")
                    Text("This branch intentionally contains no Apply or Restore button. Device writing will only be added after field-level validation, backup recovery, and compatibility tests have been reviewed.")
                        .font(.footnote)
                    Text("Reading MobileGestalt uses the original worse_query sandbox escape. This fork has not been security-audited or tested on a physical iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GestaltX-AI")
            .toolbar {
                if model.isBusy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .alert("Notice", isPresented: Binding(
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
