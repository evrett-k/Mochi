import SwiftUI

#if os(macOS)
@available(macOS 13.0, *)
struct ContentView: View {
    @State private var selection: Int = 0
    @State private var showingHelperInstallPrompt = false
    @State private var helperInstallMessage: String?
    @State private var showingHelperInstallAlert = false
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BrowsePage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Browse", systemImage: "square.grid.2x2")
            }
            .tag(0)

            NavigationStack {
                SourcesPage()
            }
            .tabItem {
                Label("Sources", systemImage: "tray.2")
            }
            .tag(1)

            NavigationStack {
                UpdatesPage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(2)

            NavigationStack {
                SearchPage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(3)
        }
        .frame(minWidth: 720, minHeight: 400)
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { SettingsView() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { DownloadsPage() }
        .task {
            if !RootHelperClient.isHelperInstalled() {
                showingHelperInstallPrompt = RootHelperClient.bundledHelperExists()
                if !RootHelperClient.bundledHelperExists() {
                    helperInstallMessage = "RootHelper is not installed and no bundled helper was found in the app."
                    showingHelperInstallAlert = true
                }
            }
        }
        .alert("Install RootHelper", isPresented: $showingHelperInstallPrompt) {
            Button("Install") {
                Task {
                    let (ok, msg) = RootHelperClient.installBundledHelper()
                    helperInstallMessage = ok ? "RootHelper installed successfully." : (msg ?? "Failed to install RootHelper")
                    showingHelperInstallAlert = true
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("RootHelper is required for privileged actions. Install it now? You will be asked for your password.")
        }
        .alert("RootHelper", isPresented: $showingHelperInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helperInstallMessage ?? "Unknown result")
        }
    }
}

#endif

#if os(macOS)
#Preview {
    if #available(macOS 13.0, *) {
        ContentView()
    } else {
        LegacyContentView()
    }
}
#endif
