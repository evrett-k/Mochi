import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct WatchUpdatesView: View {
    @State private var entries: [String] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if entries.isEmpty {
                Text("No updates available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(entries, id: \.self) { e in
                    Text(e).font(.caption)
                }
            }
        }
        .onAppear {
            Task { await loadUpdates() }
        }
    }

    private func loadUpdates() async {
        loading = true
        // Lightweight placeholder: full updates computation is heavy for watch
        await Task.sleep(200_000_000)
        entries = []
        loading = false
    }
}
#endif
