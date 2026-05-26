import SwiftUI

#if os(iOS)

@available(iOS 15.0, *)
struct LegacyContentView_iOS: View {
    @State private var selection: Int = 0
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                LegacyBrowsePage_iOS()
            }
            .toolbar { LegacyTopToolbar_iOS(appState: appState) }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationView {
                LegacySourcesPage_iOS()
            }
            .toolbar { LegacyTopToolbar_iOS(appState: appState) }
            .tabItem { Label("Sources", systemImage: "tray.2") }
            .tag(1)

            NavigationView {
                LegacyUpdatesPage_iOS()
            }
            .toolbar { LegacyTopToolbar_iOS(appState: appState) }
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            .tag(2)

            NavigationView {
                LegacySearchPage_iOS()
            }
            .toolbar { LegacyTopToolbar_iOS(appState: appState) }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(3)
        }
        .environmentObject(appState)
        .popover(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 }), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            LegacyQueuePopover_iOS()
        }
    }
}

@available(iOS 15.0, *)
private struct LegacyTopToolbar_iOS: ToolbarContent {
    @ObservedObject var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 12) {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                appState.showingDownloads = true
            } label: {
                Image(systemName: "tray.and.arrow.down")
                    .imageScale(.large)
                    .foregroundStyle(.primary)
            }

            NavigationLink {
                LegacySettingsView_iOS()
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.large)
                    .foregroundStyle(.primary)
            }
        }
    }
}

@available(iOS 15.0, *)
struct LegacyBrowsePage_iOS: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Browse")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    LegacySettingsView_iOS()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct LegacyRepositoryCard_iOS: View {
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

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

@available(iOS 15.0, *)
private struct LegacyPackageListView_iOS: View {
    let repository: RepositorySource
    @EnvironmentObject var appState: AppState
    @State private var packages: [Package] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading packages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(packages) { pkg in
                            HStack(alignment: .center, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(pkg.name).font(.headline)
                                    if let version = pkg.version {
                                        let archPart = (pkg.architecture != nil && !(pkg.architecture?.isEmpty ?? true)) ? " - \(pkg.architecture!)" : ""
                                        Text("\(version)\(archPart)").font(.caption)
                                    }
                                    if let description = pkg.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                LegacyQueueButton_iOS(repositoryURL: repository.url, pkg: pkg)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    InstallQueue.shared.enqueue(repository: repository.url, package: pkg, reason: "remove")
                                } label: {
                                    Label("Delete and add to queue", systemImage: "trash")
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 12)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color(uiColor: .separator))
                                    .frame(height: 1)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                }
            }
        }
        .task(id: repository.url) { await loadPackages() }
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
            packages = try await PackageCatalog.load(from: repository.url)
        } catch {
            errorMessage = "Failed to load packages: \(error.localizedDescription)"
        }
        loading = false
    }
}

@available(iOS 15.0, *)
private struct LegacySearchResult_iOS: Identifiable {
    let id: UUID
    let repo: String
    let pkg: Package

    init(repo: String, pkg: Package) {
        self.id = pkg.id
        self.repo = repo
        self.pkg = pkg
    }
}

@available(iOS 15.0, *)
private struct LegacyUpdateEntry_iOS: Identifiable {
    let id = UUID()
    let name: String
    let installedVersion: String
    let availableVersion: String
    let repository: String
    let package: Package
}

@available(iOS 15.0, *)
struct LegacySourcesPage_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSource = false
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(for: geometry.size.width), alignment: .leading, spacing: 12) {
                    ForEach(repositories) { repository in
                        NavigationLink(destination: LegacyPackageListView_iOS(repository: repository)) {
                            LegacyRepositoryCard_iOS(repository: repository)
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
                HStack(spacing: 12) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    LegacySettingsView_iOS()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
            LegacyAddSourceView_iOS { saved in
                if saved { repositories = RepositoryCatalog.load() }
            }
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let columns = max(1, Int(width / 220))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }
}

@available(iOS 15.0, *)
struct LegacySearchPage_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [LegacySearchResult_iOS] = []
    @State private var showingNoCache = false
    @State private var didRefreshCache = false
    @State private var installedPackageVersions: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _ in performSearch() }

                Button("Search") { performSearch() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if results.isEmpty {
                Text(query.isEmpty ? "" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                List {
                    ForEach(results) { entry in
                        HStack(alignment: .center, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.pkg.name).font(.headline)
                                HStack(spacing: 8) {
                                    if let version = entry.pkg.version {
                                        let archPart = (entry.pkg.architecture != nil && !(entry.pkg.architecture?.isEmpty ?? true)) ? " - \(entry.pkg.architecture!)" : ""
                                        Text("\(version)\(archPart)").font(.caption)
                                    }
                                    Text(entry.repo).font(.caption).foregroundStyle(.secondary)
                                }
                                if let description = entry.pkg.description {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if isInstalled(entry.pkg) {
                                Text("Installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            } else {
                                LegacyQueueButton_iOS(repositoryURL: entry.repo, pkg: entry.pkg)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                InstallQueue.shared.enqueue(repository: entry.repo, package: entry.pkg, reason: "remove")
                            } label: {
                                Label("Delete and add to queue", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(uiColor: .separator))
                                .frame(height: 1)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .listStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    Button { appState.showingDownloads = true } label: { Image(systemName: "tray.and.arrow.down") }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { LegacySettingsView_iOS() } label: { Image(systemName: "gearshape") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { installedPackageVersions = loadDpkgInstalledPackagesGlobal() }
        .onAppear { Task { await refreshCache() } }
        .sheet(isPresented: $showingNoCache) {
            VStack(spacing: 16) {
                Text("No packages found")
                Text("Open Sources and let the app fetch repositories or click Reload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Dismiss") { showingNoCache = false }
            }
            .padding(20)
            .frame(minWidth: 360, minHeight: 140)
        }
    }

    private func performSearch() {
        let all = Persistence.loadAllPackages()
        guard !all.isEmpty else {
            results = []
            showingNoCache = didRefreshCache
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            showingNoCache = false
            return
        }

        let searchQuery = trimmed.lowercased()
        var matches: [LegacySearchResult_iOS] = []
        for (repo, packages) in all {
            for package in packages {
                let nameMatch = package.name.lowercased().contains(searchQuery)
                let descriptionMatch = package.description?.lowercased().contains(searchQuery) ?? false
                let versionMatch = package.version?.lowercased().contains(searchQuery) ?? false
                if nameMatch || descriptionMatch || versionMatch {
                    matches.append(LegacySearchResult_iOS(repo: repo, pkg: package))
                }
            }
        }
        results = matches
        showingNoCache = false
    }

    private func refreshCache() async {
        let repositories = RepositoryCatalog.load()
        if repositories.isEmpty {
            await MainActor.run {
                didRefreshCache = true
                showingNoCache = Persistence.loadAllPackages().isEmpty
            }
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
            performSearch()
            didRefreshCache = true
            showingNoCache = Persistence.loadAllPackages().isEmpty
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

@available(iOS 15.0, *)
struct LegacyUpdatesPage_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var entries: [LegacyUpdateEntry_iOS] = []
    @State private var loading = false
    @State private var installMessage: String?
    @State private var showingInstallAlert = false
    @State private var installingPackageID: UUID?

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
                            Button {
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
                            } label: {
                                if installingPackageID == entry.package.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 1)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .listRowSeparator(.hidden)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(uiColor: .separator))
                                .frame(height: 1)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                    }

                    NavigationLink {
                        LegacySettingsView_iOS()
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadEntries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadEntries() }
        .alert("Update", isPresented: $showingInstallAlert) { Button("OK", role: .cancel) {} } message: { Text(installMessage ?? "") }
    }

    private func loadEntries() async {
        loading = true
        defer { loading = false }
        let installed = loadDpkgInstalledPackagesGlobal()
        let repositories = RepositoryCatalog.load()
        var out: [LegacyUpdateEntry_iOS] = []

        for repository in repositories {
            guard let packages = try? await PackageCatalog.load(from: repository.url), !packages.isEmpty else { continue }
            for package in packages {
                guard let availableVersion = package.version,
                      let installedVersion = installed[package.name.lowercased()],
                      compareVersions(availableVersion, installedVersion) == .orderedDescending else {
                    continue
                }
                out.append(LegacyUpdateEntry_iOS(name: package.name, installedVersion: installedVersion, availableVersion: availableVersion, repository: repository.url, package: package))
            }
        }

        await MainActor.run {
            entries = out
        }
    }

    private func installPackageFromRepo(pkg: Package, repositoryURL: String) async -> (Bool, String?) {
        do {
            InstallQueue.shared.enqueue(repository: repositoryURL, package: pkg, reason: "update")
            await InstallQueue.shared.installAll()
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

@available(iOS 15.0, *)
private struct LegacyDownloadsPage_iOS: View {
    var body: some View {
        Text("Queue")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@available(iOS 15.0, *)
struct LegacyQueuePopover_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = InstallQueue.shared
    @State private var installingAll = false
    @AppStorage("queueDebugLogging") private var queueDebugLogging = false
    @State private var showingDebugLogPopup = false
    @State private var debugLogLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button("Clear") { queue.clear() }
                    .disabled(queue.entries.isEmpty)
            }

            if queue.entries.isEmpty {
                Text("No queued actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(Array(queue.entries.prefix(6))) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.package.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(statusText(entry))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            InstallQueue.shared.remove(entry.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 180)
            }

            let hasActive = queue.entries.contains { $0.status == .pending || $0.status == .installing }
            Spacer()
            HStack {
                Spacer()
                if hasActive {
                    Button(action: {
                        installingAll = true
                        if queueDebugLogging {
                            debugLogLines = []
                            showingDebugLogPopup = true
                        }
                        Task {
                            await InstallQueue.shared.installAll(debugLogging: queueDebugLogging) { line in
                                DispatchQueue.main.async {
                                    debugLogLines.append(line)
                                }
                            }
                            installingAll = false
                        }
                    }) {
                        if installingAll { ProgressView().controlSize(.small) }
                        else { Text("Complete Actions") }
                    }
                    .disabled(installingAll)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 280)
        .frame(minHeight: 220)
        .sheet(isPresented: $showingDebugLogPopup) {
            LegacyQueueDebugLogPopup_iOS(logLines: $debugLogLines)
        }
    }

    private func statusText(_ entry: QueueEntry) -> String {
        switch entry.status {
        case .pending:
            let action = entry.reason.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if action.contains("install") { return "Pending install" }
            if action.contains("remove") || action.contains("uninstall") { return "Pending uninstall" }
            if action.contains("update") { return "Pending update" }
            if action.isEmpty { return "Pending" }
            return "Pending \(action)"
        case .installing: return "Installing"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }
}

@available(iOS 15.0, *)
private struct LegacyQueueDebugLogPopup_iOS: View {
    @Binding var logLines: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .navigationTitle("Queue Logs")
    }
}

@available(iOS 15.0, *)
private struct LegacySettingsView_iOS: View {
    @AppStorage("queueDebugLogging") private var queueDebugLogging = false

    var body: some View {
        Form {
            Section("Queue") {
                Toggle("Debug logging", isOn: $queueDebugLogging)
            }
        }
        .navigationTitle("Settings")
    }
}

@available(iOS 15.0, *)
private struct LegacyAddSourceView_iOS: View {
    let onSave: (Bool) -> Void
    @State private var sourceURL: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Repository URL") {
                    TextField("https://example.com", text: $sourceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onSave(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(saving || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        do {
            try RepositoryCatalog.save(sourceURL: sourceURL)
            onSave(true)
        } catch {
            errorMessage = error.localizedDescription
            onSave(false)
        }
        saving = false
    }
}

@available(iOS 15.0, *)
private struct LegacyQueueButton_iOS: View {
    @ObservedObject private var queue = InstallQueue.shared
    let repositoryURL: String
    let pkg: Package

    private var isQueued: Bool {
        queue.entries.contains { entry in
            entry.package.name == pkg.name && entry.repository == repositoryURL
        }
    }

    var body: some View {
        Button {
            InstallQueue.shared.enqueue(repository: repositoryURL, package: pkg, reason: "install")
        } label: {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Image(systemName: isQueued ? "checkmark.circle.fill" : "tray.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(isQueued ? .green : .blue)
                    .padding(8)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            } else {
                Text(isQueued ? "Queued" : "Queue")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
        }
        .buttonStyle(.plain)
        .disabled(isQueued)
        .help(isQueued ? "Already queued" : "Queue this package for download/install")
    }
}

@available(iOS 15.0, *)
private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: [.numeric, .caseInsensitive, .forcedOrdering], range: nil, locale: .current)
}

#endif
