import SwiftUI

#if os(tvOS)
@available(tvOS 15.0, *)
struct UpdatePage_tvOS: View {
    @State private var checking: Bool = false
    @State private var updates: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Updates")
                    .font(.largeTitle.bold())

                Spacer()

                if checking {
                    ProgressView()
                } else {
                    Button("Check for updates") {
                        checking = true
                        updates = []
                        Task {
                            // basic placeholder: in future compare installed vs repo versions
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            updates = [] // no updates found currently
                            checking = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !checking {
                if updates.isEmpty {
                    Text("No updates found")
                        .foregroundStyle(.secondary)
                } else {
                    List(updates, id: \.self) { u in Text(u) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(TVOSPageBackground())
    }
}
#endif
