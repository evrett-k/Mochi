import SwiftUI

#if os(iOS)
@available(iOS 16.0, *)
struct BrowsePage_iOS: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            Spacer()
            Text("Browse (iOS)")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appState.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct DownloadsPage_iOS: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Downloads / Queue (iOS)")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@available(iOS 16.0, *)
struct SettingsView_iOS: View {
    @AppStorage("queueDebugLogging") private var queueDebugLogging = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Queue")) {
                    Toggle("Debug logging", isOn: $queueDebugLogging)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#endif
