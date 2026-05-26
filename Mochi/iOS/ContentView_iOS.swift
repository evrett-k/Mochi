import SwiftUI

#if os(iOS)
@available(iOS 16.0, *)
struct ContentView_iOS: View {
    @State private var selection: Int = 0
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
                NavigationStack {
                BrowsePage_iOS()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack {
                SourcesPage_iOS()
            }
            .tabItem { Label("Sources", systemImage: "tray.2") }
            .tag(1)

            NavigationStack {
                UpdatePage_iOS()
            }
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            .tag(2)

            NavigationStack {
                SearchPage_iOS()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(3)
        }
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { SettingsView_iOS() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { DownloadsPage_iOS() }
    }
}

@available(iOS 16.0, *)
struct ContentView_iOS_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_iOS()
    }
}

#endif
