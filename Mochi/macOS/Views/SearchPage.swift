import SwiftUI

@available(macOS 13.0, *)
struct SearchResult: Identifiable {
    let id: UUID
    let repo: String
    let pkg: Package

    init(repo: String, pkg: Package) {
        self.id = pkg.id
        self.repo = repo
        self.pkg = pkg
    }
}

@available(macOS 13.0, *)
struct SearchPage: View {
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var showingNoCache = false
    @State private var installedPackageVersions: [String: String] = [:]
    @State private var installingPackageID: UUID?
    @EnvironmentObject var appState: AppState
    @State private var installMessage: String?
    @State private var showingInstallAlert = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    TextField("Search packages", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: query) { _ in performSearch() }

                    Button("Search") { performSearch() }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Group {
                    if results.isEmpty {
                        Group {
                            if query.isEmpty {
                                Text("")
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                Text("No results")
                                    .foregroundStyle(.secondary)
                                    .padding()
                            }
                        }
                    } else {
                        List {
                            ForEach(results) { entry in
                                HStack(alignment: .center, spacing: 0) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(entry.pkg.name).font(.headline)
                                        HStack(spacing: 8) {
                                            if let v = entry.pkg.version {
                                                let archPart = (entry.pkg.architecture != nil && !(entry.pkg.architecture?.isEmpty ?? true)) ? " - \(entry.pkg.architecture!)" : ""
                                                Text("\(v)\(archPart)").font(.caption)
                                            }
                                            Text(entry.repo).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let d = entry.pkg.description { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer()
                                    let isInstalled = isInstalled(entry.pkg)
                                    if isInstalled {
                                        Text("Installed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    } else {
                                        HStack(spacing: 8) {
                                            Button(action: {
                                                Task {
                                                    installingPackageID = entry.pkg.id
                                                    let (ok, msg) = await installPackageFromRepo(pkg: entry.pkg, repositoryURL: entry.repo)
                                                    installingPackageID = nil
                                                    if ok {
                                                        installedPackageVersions[entry.pkg.name.lowercased()] = entry.pkg.version
                                                        installMessage = "Installed " + entry.pkg.name
                                                    } else {
                                                        installMessage = "Install failed: " + (msg ?? "unknown")
                                                    }
                                                    showingInstallAlert = true
                                                }
                                            }) {
                                                if installingPackageID == entry.pkg.id {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                        .frame(minWidth: 56)
                                                } else {
                                                    Text("Install")
                                                        .font(.caption)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                                }
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: {
                                                InstallQueue.shared.enqueue(repository: entry.repo, package: entry.pkg, reason: "install")
                                            }) {
                                                Label("Queue", systemImage: "tray.and.arrow.down")
                                                    .font(.caption)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Queue this package for download/install")
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        InstallQueue.shared.enqueue(repository: entry.repo, package: entry.pkg, reason: "remove")
                                    } label: {
                                        Text("Delete and add to queue")
                                        Image(systemName: "trash")
                                    }
                                }
                                .padding(.vertical, 1)
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                                .listRowSeparator(.hidden)
                                Divider().background(Color.primary.opacity(0.06)).padding(.horizontal, 12)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Search Packages")
            .task {
                let all = Persistence.loadAllPackages()
                showingNoCache = all.isEmpty
                installedPackageVersions = loadDpkgInstalledPackagesGlobal()
            }
            .onAppear {
                Task { await refreshCache() }
            }
            .sheet(isPresented: $showingNoCache) {
                VStack(spacing: 16) {
                    Text("No cached packages found")
                    Text("Open Sources and let the app fetch repositories or click Reload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Dismiss") { showingNoCache = false }
                }
                .padding(20)
                .frame(minWidth: 360, minHeight: 140)
            }
            .alert("Install", isPresented: $showingInstallAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(installMessage ?? "Unknown result")
            }
        }
    }

    private func performSearch() {
        let all = Persistence.loadAllPackages()
        guard !all.isEmpty else { results = []; showingNoCache = true; return }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results = []; return }
        let q = query.lowercased()
        var out: [SearchResult] = []
        for (repo, pkgs) in all {
            for p in pkgs {
                if p.name.lowercased().contains(q) || (p.description?.lowercased().contains(q) ?? false) || (p.version?.lowercased().contains(q) ?? false) {
                    out.append(SearchResult(repo: repo, pkg: p))
                }
            }
        }
        results = out
    }

    private func refreshCache() async {
        let repos = RepositoryCatalog.load()
        if repos.isEmpty { return }
        await withTaskGroup(of: (String, [Package]?).self) { group in
            for repo in repos {
                group.addTask {
                    do { let pkgs = try await PackageCatalog.load(from: repo.url); return (repo.url, pkgs) }
                    catch { return (repo.url, nil) }
                }
            }
            for await (url, pkgs) in group {
                if let pkgs = pkgs, !pkgs.isEmpty {
                    await MainActor.run {
                        Persistence.savePackages(pkgs, for: url)
                        NotificationCenter.default.post(name: PackagesUpdatedNotification, object: nil, userInfo: ["url": url])
                    }
                }
            }
        }
        await MainActor.run {
            performSearch()
            let all = Persistence.loadAllPackages()
            showingNoCache = all.isEmpty
        }
    }

    private func isInstalled(_ pkg: Package) -> Bool {
        let installedVersion = installedPackageVersions[pkg.name.lowercased()]
        guard let pkgVersion = pkg.version?.trimmingCharacters(in: .whitespacesAndNewlines), !pkgVersion.isEmpty else {
            return installedVersion != nil
        }
        return installedVersion?.trimmingCharacters(in: .whitespacesAndNewlines) == pkgVersion
    }
}
