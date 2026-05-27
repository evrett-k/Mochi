import SwiftUI

#if os(tvOS)
struct TVOSPageBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 141/255, green: 191/255, blue: 105/255),
                Color(red: 34/255, green: 34/255, blue: 34/255)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

@available(tvOS 15.0, *)
struct ContentView_tvOS: View {
    @State private var selection: Int = 0
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                BrowsePage_tvOS()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationView {
                SourcesPage_tvOS()
            }
            .tabItem { Label("Sources", systemImage: "tray.2") }
            .tag(1)

            NavigationView {
                UpdatePage_tvOS()
            }
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            .tag(2)

            NavigationView {
                SearchPage_tvOS()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(3)
        }
        .environmentObject(appState)
        .background(TVOSPageBackground())
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { SettingsView_tvOS() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { DownloadsPage_tvOS() }
    }
}

@available(tvOS 15.0, *)
struct ContentView_tvOS_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_tvOS()
    }
}

#endif
