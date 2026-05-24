//
//  MochiApp.swift
//  Mochi
//
//  Created by michal on 5/21/26.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct MochiApp: App {
    init() {
        // No-op init. Previous attempt to set NSScroller.preferredScrollerStyle
        // caused a compile error because the property is get-only in this SDK.
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
