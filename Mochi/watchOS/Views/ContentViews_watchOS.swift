import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct ContentViews_watchOS: View {
    @StateObject private var appState = AppState()
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                WatchBrowseView()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack {
                WatchSourcesView()
            }
            .tabItem { Label("Sources", systemImage: "tray.2") }
            .tag(1)

            NavigationStack {
                WatchUpdatesView()
            }
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            .tag(2)

            NavigationStack {
                WatchSearchView()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(3)
        }
        .environmentObject(appState)
    }
}

#endif
