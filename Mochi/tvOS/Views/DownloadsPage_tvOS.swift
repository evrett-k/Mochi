import SwiftUI

#if os(tvOS)
@available(tvOS 15.0, *)
struct DownloadsPage_tvOS: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Downloads")
                    .font(.largeTitle.bold())
                Text("Download queue UI is not specialized for tvOS yet.")
                    .foregroundStyle(.secondary)
                Button("Close") {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .navigationTitle("Downloads")
        }
        .background(TVOSPageBackground())
    }
}
#endif
