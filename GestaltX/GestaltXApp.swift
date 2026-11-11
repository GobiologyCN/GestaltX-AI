//
//  GestaltXApp.swift
//  GestaltX
//

import SwiftUI

@main
struct GestaltXApp: App {
    var body: some Scene {
        WindowGroup {
            AIOnlyPreviewView()
                .environment(\.layoutDirection, Bundle.main.preferredLocalizations.first?.hasPrefix("fa") == true ? .rightToLeft : .leftToRight)
        }
    }
}
