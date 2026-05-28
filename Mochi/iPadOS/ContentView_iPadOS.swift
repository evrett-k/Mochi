import SwiftUI

#if os(iOS)
@available(iOS 16.0, *)
struct ContentView_iPadOS: View {
    private enum Section: String, CaseIterable, Identifiable {
        case browse
        case sources
        case updates
        case search

        var id: String { rawValue }

        var title: String {
            switch self {
            case .browse: return "Browse"
            case .sources: return "Sources"
            case .updates: return "Updates"
            case .search: return "Search"
            }
        }

        var icon: String {
            switch self {
            case .browse: return "square.grid.2x2"
            case .sources: return "tray.2"
            case .updates: return "arrow.triangle.2.circlepath"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selection: Section = .browse
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BrowsePage_iOS()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(Section.browse)

            NavigationStack {
                SourcesPage_iOS()
            }
            .tabItem { Label("Sources", systemImage: "tray.2") }
            .tag(Section.sources)

            NavigationStack {
                UpdatePage_iOS()
            }
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            .tag(Section.updates)

            NavigationStack {
                SearchPage_iOS()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Section.search)
        }
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { SettingsView_iOS() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { LegacyQueuePopover_iOS() }
    }

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .browse:
            NavigationStack {
                BrowsePage_iOS()
            }
        case .sources:
            NavigationStack {
                SourcesPage_iOS()
            }
        case .updates:
            UpdatePage_iOS()
        case .search:
            SearchPage_iOS()
        }
    }
}

@available(iOS 16.0, *)
struct ContentView_iPadOS_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_iPadOS()
    }
}
#endif
