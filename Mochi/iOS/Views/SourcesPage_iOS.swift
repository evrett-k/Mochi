import SwiftUI

#if os(iOS)
@available(iOS 16.0, *)
struct SourcesPage_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSource = false
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(for: geometry.size.width), alignment: .leading, spacing: 12) {
                    ForEach(repositories) { repository in
                            NavigationLink(destination: PackageListView_iOS(repository: repository)) {
                            RepositoryCard_iOS(repository: repository)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    Persistence.clearAllPackageCaches()
                    repositories = RepositoryCatalog.load()
                } label: { Image(systemName: "arrow.clockwise") }

                Button {
                    showingAddSource = true
                } label: { Image(systemName: "plus") }

                Button {
                    appState.showingSettings = true
                } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView_iOS { saved in
                if saved { repositories = RepositoryCatalog.load() }
            }
        }
    }
}

private struct RepositoryCard_iOS: View {
    let repository: RepositorySource
    @StateObject private var imageLoader: RemoteImageLoader_iOS

    init(repository: RepositorySource) {
        self.repository = repository
        _imageLoader = StateObject(wrappedValue: RemoteImageLoader_iOS(urlString: repository.url, assetName: repository.iconName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                    if let _ = imageLoader.image {
                    RepositoryIcon_iOS(urlString: repository.url, assetName: repository.iconName)
                        .frame(width: 44, height: 44)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 48, height: 48)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                Text(repository.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

@available(iOS 16.0, *)
struct PackageListView_iOS: View {
    let repository: RepositorySource
    @State private var packages: [Package] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var installMessage: String?
    @State private var showingInstallAlert = false

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading packages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                Text(err).foregroundColor(.red)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(packages) { pkg in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading) {
                                    Text(pkg.name).font(.headline)
                                    if let v = pkg.version { Text(v).font(.caption) }
                                    if let d = pkg.description { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text("Install")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    .onTapGesture {
                                        installMessage = "Install not available on iOS"
                                        showingInstallAlert = true
                                    }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            Divider().background(Color.primary.opacity(0.06)).padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .navigationTitle(repository.name)
        .task(id: repository.url) { await loadPackages() }
        .alert("Install", isPresented: $showingInstallAlert) { Button("OK", role: .cancel) {} } message: { Text(installMessage ?? "") }
    }

    private func loadPackages() async {
        loading = true
        errorMessage = nil
        if let cached = Persistence.loadPackages(for: repository.url) {
            packages = cached
            loading = false
            return
        }
        do {
            let pkgs = try await PackageCatalog.load(from: repository.url)
            packages = pkgs
        } catch {
            errorMessage = "Failed to load packages: \(error.localizedDescription)"
        }
        loading = false
    }
}

#endif
