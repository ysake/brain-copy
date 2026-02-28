//
//  BrainCopyApp.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI

@main
struct BrainCopyApp: App {
    @StateObject private var uiState = GraphUIState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(uiState)
        }
        .windowStyle(.volumetric)
    }
}
