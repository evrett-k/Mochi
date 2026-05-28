import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct WatchPackageListView: View {
    let repositoryURL: String
    @State private var packages: [Package] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let err = errorMessage {
                Text(err).foregroundColor(.red)
            } else {
                List {
                    ForEach(packages, id: \.id) { pkg in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pkg.name).font(.headline)
                                if let v = pkg.version { Text(v).font(.caption) }
                            }
                            Spacer()
                            Button {
                                InstallQueue.shared.enqueue(repository: repositoryURL, package: pkg, reason: "install")
                            } label: {
                                Image(systemName: "tray.and.arrow.down")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { Task { await loadPackages() } }
    }

    private func loadPackages() async {
        loading = true
        errorMessage = nil
        if let cached = Persistence.loadPackages(for: repositoryURL) {
            packages = cached
            loading = false
            return
        }
        do {
            packages = try await PackageCatalog.load(from: repositoryURL)
        } catch {
            errorMessage = "Failed to load packages: \(error.localizedDescription)"
        }
        loading = false
    }
}
#endif
