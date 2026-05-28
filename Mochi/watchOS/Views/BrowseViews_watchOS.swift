import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct WatchBrowseView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Browse")
                    .font(.headline)
                Text("Browse repositories on your iPhone for full details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
#endif
