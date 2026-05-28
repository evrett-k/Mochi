import SwiftUI

#if os(tvOS)
@available(tvOS 15.0, *)
struct SettingsView_tvOS: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.largeTitle.bold())
                Text("tvOS uses a simplified settings sheet for now.")
                    .foregroundStyle(.secondary)
                Button("Close") {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .navigationTitle("Settings")
        }
        .background(TVOSPageBackground())
    }
}
#endif
