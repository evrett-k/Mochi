import SwiftUI

struct LegacyContentView: View {
    @State private var selection: Int = 0
    @State private var showingHelperInstallPrompt = false
    @State private var helperInstallMessage: String?
    @State private var showingHelperInstallAlert = false
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                BrowsePage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Queue", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Browse", systemImage: "square.grid.2x2")
            }
            .tag(0)

            NavigationView {
                LegacySourcesPage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Queue", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Sources", systemImage: "tray.2")
            }
            .tag(1)

            NavigationView {
                LegacyUpdatesPage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Queue", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(2)

            NavigationView {
                LegacySearchPage()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Queue", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(3)
        }
        .frame(minWidth: 720, minHeight: 400)
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { LegacySettingsView() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { LegacyDownloadsPage() }
        .task {
            if !RootHelperClient.isHelperInstalled() {
                showingHelperInstallPrompt = RootHelperClient.bundledHelperExists()
                if !RootHelperClient.bundledHelperExists() {
                    helperInstallMessage = "RootHelper is not installed and no bundled helper was found in the app."
                    showingHelperInstallAlert = true
                }
            }
        }
        .alert("Install RootHelper", isPresented: $showingHelperInstallPrompt) {
            Button("Install") {
                Task {
                    let (ok, msg) = RootHelperClient.installBundledHelper()
                    helperInstallMessage = ok ? "RootHelper installed successfully." : (msg ?? "Failed to install RootHelper")
                    showingHelperInstallAlert = true
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("RootHelper is required for privileged actions. Install it now? You will be asked for your password.")
        }
        .alert("RootHelper", isPresented: $showingHelperInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(helperInstallMessage ?? "Unknown result")
        }
    }
}

private struct LegacySourcesPage: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSource = false
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(for: geometry.size.width), alignment: .leading, spacing: 12) {
                    ForEach(repositories) { repository in
                        NavigationLink(destination: LegacyPackageListView(repository: repository)) {
                            LegacyRepositoryCard(repository: repository)
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
        }
        .sheet(isPresented: $showingAddSource) {
            LegacyAddSourceView { saved in
                if saved {
                    repositories = RepositoryCatalog.load()
                }
            }
        }
    }
}

private struct LegacyRepositoryCard: View {
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

private struct LegacyQueueButton: View {
    let repositoryURL: String
    let pkg: Package

    var body: some View {
        Button(action: {
            InstallQueue.shared.enqueue(repository: repositoryURL, package: pkg, reason: "install")
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

private struct LegacyPackageListView: View {
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

                                        LegacyQueueButton(repositoryURL: repository.url, pkg: pkg)
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

private struct LegacySearchResult: Identifiable {
    let id: UUID
    let repo: String
    let pkg: Package

    init(repo: String, pkg: Package) {
        self.id = pkg.id
        self.repo = repo
        self.pkg = pkg
    }
}

private struct LegacyUpdateEntry: Identifiable {
    let id = UUID()
    let name: String
    let installedVersion: String
    let availableVersion: String
    let repository: String
    let package: Package
}

private struct LegacySearchPage: View {
    @State private var query: String = ""
    @State private var results: [LegacySearchResult] = []
    @State private var showingNoCache = false
    @State private var installedPackageVersions: [String: String] = [:]
    @State private var installingPackageID: UUID?
    @EnvironmentObject var appState: AppState
    @State private var installMessage: String?
    @State private var showingInstallAlert = false

    var body: some View {
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
                            Divider().background(Color.primary.opacity(0.06)).padding(.horizontal, 12)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
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

    private func performSearch() {
        let all = Persistence.loadAllPackages()
        guard !all.isEmpty else { results = []; showingNoCache = true; return }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results = []; return }
        let q = query.lowercased()
        var out: [LegacySearchResult] = []
        for (repo, pkgs) in all {
            for p in pkgs {
                if p.name.lowercased().contains(q) || (p.description?.lowercased().contains(q) ?? false) || (p.version?.lowercased().contains(q) ?? false) {
                    out.append(LegacySearchResult(repo: repo, pkg: p))
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
            showingNoCache = Persistence.loadAllPackages().isEmpty
            installedPackageVersions = loadDpkgInstalledPackagesGlobal()
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

private struct LegacyUpdatesPage: View {
    @State private var entries: [LegacyUpdateEntry] = []
    @State private var loading = false
    @State private var installMessage: String?
    @State private var showingInstallAlert = false
    @State private var installingPackageID: UUID?
    @EnvironmentObject var appState: AppState

    var body: some View {
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

        let newEntries = bestByName.compactMap { name, pair -> LegacyUpdateEntry? in
            guard let installedVersion = installed[name] else { return nil }
            return LegacyUpdateEntry(
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

private struct LegacyDownloadsPage: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = InstallQueue.shared
    @State private var installingAll = false

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                if queue.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No queued downloads")
                            .font(.headline)
                        Text("Queue packages or updates from Sources, Search, or Updates, then install them in order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                } else {
                    List {
                        ForEach(queue.entries) { e in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.package.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(e.repository)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if !e.missingDependencies.isEmpty {
                                        Text("Missing deps: " + e.missingDependencies.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(statusText(e))
                                        .font(.caption)
                                        .foregroundStyle(e.status == .failed ? .red : .secondary)
                                    if let message = e.message, !message.isEmpty {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Button(action: {
                                    InstallQueue.shared.remove(e.id)
                                }) {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Remove from queue")
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.primary.opacity(0.03))
                        }
                        .onDelete { idx in
                            for i in idx { InstallQueue.shared.remove(queue.entries[i].id) }
                        }
                    }
                    .listStyle(.plain)
                }

                let hasActive = queue.entries.contains { $0.status == .pending || $0.status == .installing }

                if hasActive {
                    HStack(spacing: 10) {
                        Button("Clear") { InstallQueue.shared.clear() }
                        Spacer()
                        Button(action: {
                            installingAll = true
                            Task {
                                await InstallQueue.shared.installAll()
                                installingAll = false
                            }
                        }) {
                            if installingAll { ProgressView().controlSize(.small) }
                            else { Text("Complete Actions") }
                        }
                        .disabled(installingAll)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func statusText(_ e: QueueEntry) -> String {
        switch e.status {
        case .pending:
            let action = e.reason.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if action.contains("install") { return "Pending install" }
            if action.contains("remov") || action.contains("uninstall") { return "Pending uninstall" }
            if action.contains("update") { return "Pending update" }
            if action.isEmpty { return "Pending" }
            return "Pending \(action)"
        case .installing: return "Installing"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }
}

private struct LegacySettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Color.clear
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct LegacyAddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var errorMessage: String?

    let onSave: (Bool) -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("", text: $sourceURL, prompt: Text("https://apt.procurs.us/"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                HStack {
                    Spacer()
                    Button("Cancel") {
                        onSave(false)
                        dismiss()
                    }
                    Button("Add") {
                        if RootHelperClient.isHelperInstalled() {
                            let (success, message) = RootHelperClient.addRepository(url: sourceURL)
                            if success {
                                errorMessage = nil
                                Persistence.clearCache(for: sourceURL)
                                onSave(true)
                                dismiss()
                            } else {
                                errorMessage = message ?? "Unknown helper error"
                                onSave(false)
                            }
                        } else {
                            do {
                                try RepositoryCatalog.save(sourceURL: sourceURL)
                                errorMessage = nil
                                Persistence.clearCache(for: sourceURL)
                                onSave(true)
                                dismiss()
                            } catch {
                                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                errorMessage = msg
                                onSave(false)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceURL.isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Source")
            .padding(20)
            .frame(minWidth: 360, minHeight: 160)
        }
    }
}
