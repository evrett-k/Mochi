import SwiftUI

struct SourcesPage: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSource = false
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(columns: gridColumns(for: geometry.size.width), alignment: .leading, spacing: 12) {
                        ForEach(repositories) { repository in
                            NavigationLink(destination: PackageListView(repository: repository)) {
                                RepositoryCard(repository: repository)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Persistence.clearAllPackageCaches()
                        repositories = RepositoryCatalog.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload repositories and clear package cache")

                    Button {
                        showingAddSource = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                // Queue and Settings are provided by the host NavigationStack toolbar
            }
            .sheet(isPresented: $showingAddSource) {
                AddSourceView { saved in
                    if saved {
                        repositories = RepositoryCatalog.load()
                    }
                }
            }
        }
    }
}

private struct QueueButton: View {
    let repositoryURL: String
    let pkg: Package

    var body: some View {
        Button(action: {
            InstallQueue.shared.enqueue(repository: repositoryURL, package: pkg, reason: "install")
        }) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text("Queue")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("Queue this package for download/install")
    }
}

private struct RepositoryCard: View {
    let repository: RepositorySource
    @StateObject private var imageLoader: RemoteImageLoader

    init(repository: RepositorySource) {
        self.repository = repository
        _imageLoader = StateObject(wrappedValue: RemoteImageLoader(urlString: repository.url, assetName: repository.iconName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let image = imageLoader.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 48, height: 48)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(repository.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PackageListView: View {
    let repository: RepositorySource
    @State private var packages: [Package] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var installingPackageID: UUID?
    @State private var installMessage: String?
    @State private var showingInstallAlert = false
    @State private var installedPackageVersions: [String: String] = [:]
    @State private var dpkgInstalledPackages: [String: String] = [:]

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
                            HStack(alignment: .center, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(pkg.name).font(.headline)
                                    HStack {
                                        if let v = pkg.version {
                                            let archPart = (pkg.architecture != nil && !(pkg.architecture?.isEmpty ?? true)) ? " - \(pkg.architecture!)" : ""
                                            Text("\(v)\(archPart)").font(.caption)
                                        }
                                    }
                                    if let d = pkg.description { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                let isInstalled = isInstalled(pkg)
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
                                            Task { await installPackage(pkg) }
                                        }) {
                                            if installingPackageID == pkg.id {
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

                                        QueueButton(repositoryURL: repository.url, pkg: pkg)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    InstallQueue.shared.enqueue(repository: repository.url, package: pkg, reason: "remove")
                                } label: {
                                    Text("Delete and add to queue")
                                    Image(systemName: "trash")
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 12)
                            Divider().background(Color.primary.opacity(0.06)).padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .navigationTitle(repository.name)
        .task(id: repository.url) {
            await loadPackages()
        }
        .onReceive(NotificationCenter.default.publisher(for: PackagesUpdatedNotification)) { note in
            if let info = note.userInfo, let url = info["url"] as? String, url == repository.url {
                DispatchQueue.main.async {
                    if let cached = Persistence.loadPackages(for: repository.url) {
                        packages = cached
                        Task { await checkInstalledForPackages() }
                    }
                }
            }
        }
        .alert("Install", isPresented: $showingInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installMessage ?? "Unknown result")
        }
    }

    private func installPackage(_ pkg: Package) async {
        installingPackageID = pkg.id
        defer { installingPackageID = nil }

        guard let _ = pkg.version else {
            installMessage = "Package missing version"
            showingInstallAlert = true
            return
        }
        let (ok, msg) = await installPackageFromRepo(pkg: pkg, repositoryURL: repository.url)
        if ok {
            installedPackageVersions[pkg.name.lowercased()] = pkg.version
            installMessage = "Installed " + pkg.name
        } else {
            installMessage = "Install failed: " + (msg ?? "unknown")
        }
        showingInstallAlert = true
    }

    private func loadPackages() async {
        loading = true
        errorMessage = nil
        if let cached = Persistence.loadPackages(for: repository.url) {
            packages = cached
            loading = false
            Task { await checkInstalledForPackages() }
            return
        }

        do {
            let pkgs = try await PackageCatalog.load(from: repository.url)
            packages = pkgs
            Task { await checkInstalledForPackages() }
        } catch {
            errorMessage = "Failed to load packages: \(error.localizedDescription)"
        }
        loading = false
    }

    private func checkInstalledForPackages() async {
        let names = packages.map { $0.name }
        var present: Set<String> = []
        if dpkgInstalledPackages.isEmpty {
            let loaded = loadDpkgInstalledPackages()
            await MainActor.run {
                dpkgInstalledPackages = loaded
            }
        }

        await withTaskGroup(of: (String, Bool).self) { group in
            for n in names {
                group.addTask {
                    (n, await isEffectivelyInstalledAsync(n))
                }
            }
            for await (name, ok) in group {
                if ok { present.insert(name) }
            }
        }
        await MainActor.run {
            for name in present {
                if installedPackageVersions[name.lowercased()] == nil {
                    installedPackageVersions[name.lowercased()] = packages.first(where: { $0.name.lowercased() == name.lowercased() })?.version
                }
            }
        }
    }

    private func isCLIPresentAsync(_ name: String) async -> Bool {
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let which = "/usr/bin/which"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: which)
                p.arguments = [name]
                do {
                    try p.run()
                    p.waitUntilExit()
                    cont.resume(returning: p.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }

    private func isEffectivelyInstalledAsync(_ name: String) async -> Bool {
        if !dpkgInstalledPackages.isEmpty {
            return dpkgInstalledPackages[name.lowercased()] != nil
        }
        return await isCLIPresentAsync(name)
    }

    private func loadDpkgInstalledPackages() -> [String: String] {
        let statusPath = "/opt/procursus/var/lib/dpkg/status"
        var out: [String: String] = [:]
        guard FileManager.default.fileExists(atPath: statusPath) else { return out }
        do {
            let txt = try String(contentsOfFile: statusPath, encoding: .utf8)
            let blocks = txt.components(separatedBy: "\n\n")
            for block in blocks {
                var pkgName: String?
                var pkgVersion: String?
                var okInstalled = false
                for line in block.split(separator: "\n") {
                    let s = String(line)
                    if s.hasPrefix("Package:") {
                        pkgName = value(after: "Package:", in: s)
                    } else if s.hasPrefix("Version:") {
                        pkgVersion = value(after: "Version:", in: s)
                    } else if s.hasPrefix("Status:") {
                        let rest = value(after: "Status:", in: s) ?? ""
                        if rest.contains("install ok installed") { okInstalled = true }
                    }
                }
                if let n = pkgName, okInstalled {
                    out[n.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = pkgVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            NSLog("[PackageListView] failed reading dpkg status: %@", String(describing: error))
        }
        return out
    }

    private func isInstalled(_ pkg: Package) -> Bool {
        let installedVersion = installedPackageVersions[pkg.name.lowercased()]
        guard let pkgVersion = pkg.version?.trimmingCharacters(in: .whitespacesAndNewlines), !pkgVersion.isEmpty else {
            return installedVersion != nil
        }
        return installedVersion?.trimmingCharacters(in: .whitespacesAndNewlines) == pkgVersion
    }
}
