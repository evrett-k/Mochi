import SwiftUI

@available(iOS 16.0, *)
struct SearchResult_iOS: Identifiable {
    let id: UUID
    let repo: String
    let pkg: Package

    init(repo: String, pkg: Package) {
        self.id = pkg.id
        self.repo = repo
        self.pkg = pkg
    }
}

@available(iOS 16.0, *)
struct SearchPage_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [SearchResult_iOS] = []
    @State private var showingNoCache = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    } else {
                        Text("No results for \"\(query)\"")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                } else {
                    List {
                        ForEach(results) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.pkg.name)
                                    .font(.headline)

                                HStack(spacing: 8) {
                                    if let version = entry.pkg.version {
                                        Text(version)
                                    }

                                    Text(entry.repo)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)

                                if let description = entry.pkg.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search packages")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            appState.showingDownloads = true
                        } label: { Image(systemName: "tray.and.arrow.down") }

                        NavigationLink { SettingsView_iOS() } label: { Image(systemName: "gearshape") }
                    }
                }
            }
            .onChange(of: query) { _ in
                performSearch()
            }
            .task {
                await refreshCache()
                performSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: PackagesUpdatedNotification)) { _ in
                performSearch()
            }
            .sheet(isPresented: $showingNoCache) {
                VStack(spacing: 16) {
                    Text("No packages found")
                    Text("Open Sources and let the app fetch repositories, then search again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Dismiss") { showingNoCache = false }
                }
                .padding(20)
                .frame(minWidth: 360, minHeight: 140)
            }
        }
    }

    private func performSearch() {
        let all = Persistence.loadAllPackages()
        guard !all.isEmpty else {
            results = []
            showingNoCache = true
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            showingNoCache = false
            return
        }

        let searchQuery = trimmedQuery.lowercased()
        var matches: [SearchResult_iOS] = []

        for (repo, packages) in all {
            for package in packages {
                let nameMatch = package.name.lowercased().contains(searchQuery)
                let descriptionMatch = package.description?.lowercased().contains(searchQuery) ?? false
                let versionMatch = package.version?.lowercased().contains(searchQuery) ?? false

                if nameMatch || descriptionMatch || versionMatch {
                    matches.append(SearchResult_iOS(repo: repo, pkg: package))
                }
            }
        }

        results = matches
        showingNoCache = false
    }

    private func refreshCache() async {
        let repositories = RepositoryCatalog.load()
        if repositories.isEmpty {
            return
        }

        await withTaskGroup(of: (String, [Package]?).self) { group in
            for repository in repositories {
                group.addTask {
                    do {
                        let packages = try await PackageCatalog.load(from: repository.url)
                        return (repository.url, packages)
                    } catch {
                        return (repository.url, nil)
                    }
                }
            }

            for await (repositoryURL, packages) in group {
                if let packages, !packages.isEmpty {
                    await MainActor.run {
                        Persistence.savePackages(packages, for: repositoryURL)
                        NotificationCenter.default.post(name: PackagesUpdatedNotification, object: nil, userInfo: ["url": repositoryURL])
                    }
                }
            }
        }

        await MainActor.run {
            showingNoCache = Persistence.loadAllPackages().isEmpty
        }
    }
}

@available(iOS 16.0, *)
struct SearchPage_iOS_Previews: PreviewProvider {
    static var previews: some View {
        SearchPage_iOS()
    }
}
