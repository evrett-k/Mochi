import SwiftUI

struct UpdateEntry: Identifiable {
    let id = UUID()
    let name: String
    let installedVersion: String
    let availableVersion: String
    let repository: String
    let package: Package
}

struct UpdatesPage: View {
    @State private var entries: [UpdateEntry] = []
    @State private var loading = false
    @State private var installMessage: String?
    @State private var showingInstallAlert = false
    @State private var installingPackageID: UUID?
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Checking updates…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    VStack(spacing: 10) {
                        Text("No updates available")
                            .font(.headline)
                        Text("Installed packages already match the cached repository versions.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(entries) { entry in
                            HStack(alignment: .center, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.name).font(.headline)
                                    Text("Installed \(entry.installedVersion) • Available \(entry.availableVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.repository)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(action: {
                                    Task {
                                        installingPackageID = entry.package.id
                                        let (ok, msg) = await installPackageFromRepo(pkg: entry.package, repositoryURL: entry.repository)
                                        installingPackageID = nil
                                        if ok {
                                            installMessage = "Installed " + entry.name
                                            await loadEntries()
                                        } else {
                                            installMessage = "Install failed: " + (msg ?? "unknown")
                                        }
                                        showingInstallAlert = true
                                    }
                                }) {
                                    if installingPackageID == entry.package.id {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(minWidth: 56)
                                    } else {
                                        Text("Update")
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    }
                                }
                                .buttonStyle(.plain)
                                Button(action: {
                                    InstallQueue.shared.enqueue(repository: entry.repository, package: entry.package, reason: "update")
                                }) {
                                    Label("Queue", systemImage: "tray.and.arrow.down")
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                                .help("Queue this update for later installation")
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
            .navigationTitle("Updates")
            .task { await loadEntries() }
            .alert("Update", isPresented: $showingInstallAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(installMessage ?? "Unknown result")
            }
        }
    }

    private func loadEntries() async {
        loading = true
        defer { loading = false }

        let installed = loadDpkgInstalledPackagesGlobal()
        let all = Persistence.loadAllPackages()
        var bestByName: [String: (Package, String)] = [:]

        for (repo, packages) in all {
            for pkg in packages {
                guard let version = pkg.version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else { continue }
                let name = pkg.name.lowercased()
                guard let installedVersion = installed[name], !installedVersion.isEmpty else { continue }
                guard compareVersions(version, installedVersion) == .orderedDescending else { continue }

                if let existing = bestByName[name] {
                    if compareVersions(version, existing.0.version ?? "") == .orderedDescending {
                        bestByName[name] = (pkg, repo)
                    }
                } else {
                    bestByName[name] = (pkg, repo)
                }
            }
        }

        let newEntries = bestByName.compactMap { name, pair -> UpdateEntry? in
            guard let installedVersion = installed[name] else { return nil }
            return UpdateEntry(
                name: pair.0.name,
                installedVersion: installedVersion,
                availableVersion: pair.0.version ?? "",
                repository: pair.1,
                package: pair.0
            )
        }
        entries = newEntries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
