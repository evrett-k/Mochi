import SwiftUI

#if os(iOS)
@available(iOS 15.0, *)
struct LegacyContentView_iPadOS: View {
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
            NavigationView { LegacyBrowsePage_iOS() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
                .tag(Section.browse)

            NavigationView { LegacySourcesPage_iOS() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Sources", systemImage: "tray.2") }
                .tag(Section.sources)

            NavigationView { LegacyUpdatesPage_iOS() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                .tag(Section.updates)

            NavigationView { LegacySearchPage_iOS() }
                .navigationViewStyle(.stack)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Section.search)
        }
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) {
            LegacyQueuePopover_iOS()
        }
    }

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .browse:
            NavigationView { LegacyBrowsePage_iOS() }
                .navigationViewStyle(.stack)
        case .sources:
            NavigationView { LegacySourcesPage_iOS() }
                .navigationViewStyle(.stack)
        case .updates:
            NavigationView { LegacyUpdatesPage_iOS() }
                .navigationViewStyle(.stack)
        case .search:
            NavigationView { LegacySearchPage_iOS() }
                .navigationViewStyle(.stack)
        }
    }
}

@available(iOS 15.0, *)
struct LegacyContentView_iPadOS_Previews: PreviewProvider {
    static var previews: some View {
        LegacyContentView_iPadOS()
    }
}
#endif
