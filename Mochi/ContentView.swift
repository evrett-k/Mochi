//
//  ContentView.swift
//  Mochi
//
//  Created by michal on 5/21/26.
//

import SwiftUI
import Combine
import Compression
import AppKit
import Foundation

let PackagesUpdatedNotification = Notification.Name("PackagesUpdated")

final class AppState: ObservableObject {
    @Published var showingDownloads: Bool = false
    @Published var showingSettings: Bool = false
}

fileprivate func value(after prefix: String, in line: String) -> String? {
    guard line.hasPrefix(prefix) else { return nil }
    let start = line.index(line.startIndex, offsetBy: prefix.count)
    return line[start...].trimmingCharacters(in: .whitespaces)
}

fileprivate func loadDpkgInstalledPackagesGlobal() -> [String: String] {
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
        NSLog("[Global] failed reading dpkg status: %@", String(describing: error))
    }
    return out
}

fileprivate func isCLIPresentSync(_ name: String) -> Bool {
    let which = "/usr/bin/which"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: which)
    p.arguments = [name]
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    } catch {
        return false
    }
}

fileprivate func installPackageFromRepo(pkg: Package, repositoryURL: String) async -> (Bool, String?) {
    guard let version = pkg.version else { return (false, "Package missing version") }

    NSLog("[installPackageFromRepo] start pkg=%@ repo=%@", pkg.name, repositoryURL)

    if isCLIPresentSync(pkg.name) {
        NSLog("[installPackageFromRepo] skipping because %@ exists on PATH", pkg.name)
        return (false, "\(pkg.name) already present on PATH")
    }

    let base = repositoryURL.hasSuffix("/") ? repositoryURL : repositoryURL + "/"

    if let filename = pkg.filename, !filename.isEmpty, let url = URL(string: filename, relativeTo: URL(string: base)) {
        do {
            NSLog("[installPackageFromRepo] trying filename URL %@", url.absoluteString)
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 0 {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try data.write(to: tmp)
                let (ok, msg) = RootHelperClient.installDeb(atPath: tmp.path)
                try? FileManager.default.removeItem(at: tmp)
                NSLog("[installPackageFromRepo] filename install %@ msg=%@", ok ? "succeeded" : "failed", msg ?? "nil")
                return (ok, msg)
            }
        } catch {
            NSLog("[installPackageFromRepo] filename fetch failed for %@: %@", filename, String(describing: error))
        }
    }

    if let resolvedFilename = await resolveFilenameFromRepository(pkg: pkg, repositoryURL: repositoryURL),
       let url = URL(string: resolvedFilename, relativeTo: URL(string: base)) {
        do {
            NSLog("[installPackageFromRepo] trying resolved repo filename URL %@", url.absoluteString)
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 0 {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try data.write(to: tmp)
                let (ok, msg) = RootHelperClient.installDeb(atPath: tmp.path)
                try? FileManager.default.removeItem(at: tmp)
                NSLog("[installPackageFromRepo] resolved filename install %@ msg=%@", ok ? "succeeded" : "failed", msg ?? "nil")
                return (ok, msg)
            }
        } catch {
            NSLog("[installPackageFromRepo] resolved filename fetch failed for %@: %@", resolvedFilename, String(describing: error))
        }
    }

    let archPart = pkg.architecture ?? ""
    var candidates: [String] = []
    if !archPart.isEmpty {
        candidates.append("\(pkg.name)_\(version)_\(archPart).deb")
        candidates.append("\(pkg.name)-\(version)-\(archPart).deb")
    }
    candidates.append("\(pkg.name)_\(version).deb")
    candidates.append("\(pkg.name)-\(version).deb")

    let probes = ["", "pool/", "pool/main/"]

    var downloadedURL: URL? = nil
    for name in candidates {
        for probe in probes {
            let s = base + probe + name
            guard let url = URL(string: s) else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 0 {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try data.write(to: tmp)
                    downloadedURL = tmp
                    NSLog("[installPackageFromRepo] fetched fallback URL %@", url.absoluteString)
                    break
                }
            } catch {
                continue
            }
        }
        if downloadedURL != nil { break }
    }

    guard let local = downloadedURL else { return (false, "Could not find .deb") }

    let (ok, msg) = RootHelperClient.installDeb(atPath: local.path)
    try? FileManager.default.removeItem(at: local)
    NSLog("[installPackageFromRepo] fallback install %@ msg=%@", ok ? "succeeded" : "failed", msg ?? "nil")
    return (ok, msg)
}

fileprivate func resolveFilenameFromRepository(pkg: Package, repositoryURL: String) async -> String? {
    let targetName = pkg.name.lowercased()
    let targetVersion = pkg.version?.lowercased()
    let targetArch = pkg.architecture?.lowercased()

    if let cachedPackages = Persistence.loadPackages(for: repositoryURL) {
        NSLog("[resolveFilenameFromRepository] checking cached packages for %@", pkg.name)
        if let match = bestFilenameMatch(in: cachedPackages, targetName: targetName, targetVersion: targetVersion, targetArch: targetArch) {
            return match
        }
    }

    do {
        let packages = try await PackageCatalog.load(from: repositoryURL)
        NSLog("[resolveFilenameFromRepository] checking refreshed packages for %@", pkg.name)
        if let match = bestFilenameMatch(in: packages, targetName: targetName, targetVersion: targetVersion, targetArch: targetArch) {
            return match
        }
    } catch {
        NSLog("[resolveFilenameFromRepository] refresh failed for %@: %@", repositoryURL, String(describing: error))
    }
    return nil
}

fileprivate func bestFilenameMatch(in packages: [Package], targetName: String, targetVersion: String?, targetArch: String?) -> String? {
    let candidates = packages.filter { candidate in
        candidate.name.lowercased() == targetName && candidate.filename != nil
    }

    if let exact = candidates.first(where: { candidate in
        candidate.version?.lowercased() == targetVersion
        && (targetArch == nil || candidate.architecture?.lowercased() == targetArch)
    }) {
        return exact.filename
    }

    if let versionMatch = candidates.first(where: { candidate in
        candidate.version?.lowercased() == targetVersion
    }) {
        return versionMatch.filename
    }

    if candidates.count == 1 {
        return candidates[0].filename
    }

    if let first = candidates.first {
        NSLog("[bestFilenameMatch] falling back to first candidate %@ for %@", first.filename ?? "nil", targetName)
        return first.filename
    }

    return nil
}

private struct SourcesPage: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSource = false
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()
    @State private var nonResponsive: [RepositorySource] = []
    @State private var showingNoResponseSheet = false

    var body: some View {
        GeometryReader { geometry in
            let columns = gridColumns(for: geometry.size.width)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(repositories) { repository in
                        NavigationLink(destination: PackageListView(repository: repository)) {
                            RepositoryCard(repository: repository)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem {
                Button {
                    Persistence.clearAllPackageCaches()
                    repositories = RepositoryCatalog.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload repositories and clear package cache")
            }

            ToolbarItem {
                Button {
                    showingAddSource = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Label("Downloads", systemImage: "tray.and.arrow.down")
                }
            }

            ToolbarItem {
                Button {
                    appState.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }

        .sheet(isPresented: $showingAddSource) {
            AddSourceView { saved in
                if saved {
                    repositories = RepositoryCatalog.load()
                }
            }
        }
        .task {
            repositories = RepositoryCatalog.load()
            for repo in repositories {
                Task.detached {
                    do {
                        let pkgs = try await PackageCatalog.load(from: repo.url)
                        if !pkgs.isEmpty {
                            await MainActor.run {
                                Persistence.savePackages(pkgs, for: repo.url)
                                NotificationCenter.default.post(name: PackagesUpdatedNotification, object: nil, userInfo: ["url": repo.url])
                            }
                        } else {
                            Task { @MainActor in
                                if !nonResponsive.contains(where: { $0.url == repo.url }) {
                                    nonResponsive.append(repo)
                                    showingNoResponseSheet = true
                                }
                            }
                        }
                    } catch {
                        NSLog("[SourcesPage] background update failed for %@: %@", repo.url, String(describing: error))
                        Task { @MainActor in
                            if !nonResponsive.contains(where: { $0.url == repo.url }) {
                                nonResponsive.append(repo)
                                showingNoResponseSheet = true
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingNoResponseSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Some repositories did not respond with packages:")
                        .font(.headline)

                    List {
                        ForEach(nonResponsive) { r in
                            VStack(alignment: .leading) {
                                Text(r.name).font(.body)
                                Text(r.url).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Retry") {
                            Task {
                                await retryNonResponsive()
                            }
                        }
                        Button("Dismiss") {
                            nonResponsive.removeAll()
                            showingNoResponseSheet = false
                        }
                    }
                }
                .padding(16)
                .navigationTitle("No Packages")
            }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func retryNonResponsive() async {
        let reposToTry = nonResponsive
        nonResponsive.removeAll()
        for repo in reposToTry {
            do {
                let pkgs = try await PackageCatalog.load(from: repo.url)
                if !pkgs.isEmpty {
                    Persistence.savePackages(pkgs, for: repo.url)
                    NotificationCenter.default.post(name: PackagesUpdatedNotification, object: nil, userInfo: ["url": repo.url])
                } else {
                    Task { @MainActor in nonResponsive.append(repo); showingNoResponseSheet = true }
                }
            } catch {
                Task { @MainActor in nonResponsive.append(repo); showingNoResponseSheet = true }
            }
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let count: Int

        if width < 520 {
            count = 2
        } else if width < 760 {
            count = 3
        } else if width < 1040 {
            count = 4
        } else {
            count = 5
        }

        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

private struct RepositorySource: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let iconName: String
}

private enum RepositoryCatalog {
    private static let sourcesFileURL = URL(fileURLWithPath: "/opt/procursus/etc/apt/sources.list.d/procursus.sources")

    static func load() -> [RepositorySource] {
        guard let contents = try? String(contentsOf: sourcesFileURL, encoding: .utf8) else {
            return [fallbackRepository]
        }

        let repositories = parse(contents: contents)
        return repositories.isEmpty ? [fallbackRepository] : repositories
    }

    static func save(sourceURL: String) throws {
        let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repositoryURL = URL(string: trimmedURL), repositoryURL.scheme != nil else {
            throw RepositoryCatalogError.invalidURL
        }

        try FileManager.default.createDirectory(
            at: sourcesFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existingContents = (try? String(contentsOf: sourcesFileURL, encoding: .utf8)) ?? ""

        if containsRepositoryURL(trimmedURL, in: existingContents) {
            return
        }

        let newEntry = sourceEntryText(for: trimmedURL)
        let updatedContents: String
        if existingContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedContents = newEntry
        } else {
            updatedContents = existingContents.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + newEntry
        }

        try updatedContents.write(to: sourcesFileURL, atomically: true, encoding: .utf8)
    }

    private static func sourceEntryText(for repositoryURL: String) -> String {
        [
            "Types: deb",
            "URIs: \(repositoryURL)",
            "Suites: ./",
            "Components: main"
        ].joined(separator: "\n")
    }

    private static var fallbackRepository: RepositorySource {
        RepositorySource(
            name: "Procursus",
            url: "https://apt.procurs.us/",
            iconName: "CydiaIcon"
        )
    }

    private static func parse(contents: String) -> [RepositorySource] {
        contents
            .components(separatedBy: "\n\n")
            .compactMap(parseEntry)
            .flatMap { entry in
                entry.uris.map { uri in
                        let name = entry.label ?? repositoryName(for: uri)
                        return RepositorySource(
                            name: name,
                            url: uri,
                            iconName: iconNameFor(label: entry.label, uri: uri)
                        )
                    }
            }
    }

    nonisolated private static func parseEntry(_ block: String) -> SourcesEntry? {
        var label: String?
        var uris: [String] = []

        for rawLine in block.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = line.firstIndex(of: ":") else { continue }

            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "label":
                label = value
            case "uris":
                let newUris = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                uris.append(contentsOf: newUris)
            default:
                continue
            }
        }

        guard !uris.isEmpty else { return nil }
        return SourcesEntry(label: label, uris: uris)
    }

    private static func containsRepositoryURL(_ repositoryURL: String, in contents: String) -> Bool {
        contents
            .components(separatedBy: "\n\n")
            .contains { block in
                block.contains("URIs: \(repositoryURL)")
            }
    }

    private static func repositoryName(for uri: String) -> String {
        URL(string: uri)?.host.map { host in
            host.hasPrefix("apt.") ? String(host.dropFirst(4)) : host
        } ?? "Repository"
    }

    private static func sanitize(_ s: String) -> String {
        let parts = s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.map { $0.capitalized }.joined()
    }

    private static func iconNameFor(label: String?, uri: String) -> String {
        var candidates: [String] = []

        if let label = label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            let s = sanitize(label)
            candidates.append(s + "Icon")
            candidates.append(s)
        }

        if let host = URL(string: uri)?.host {
            let s = sanitize(host)
            candidates.append(s + "Icon")
            candidates.append(s)
            candidates.append(host)
        }

        for c in candidates {
            if NSImage(named: NSImage.Name(c)) != nil {
                return c
            }
        }

        return "CydiaIcon"
    }

    private struct SourcesEntry {
        let label: String?
        let uris: [String]
    }

    private enum RepositoryCatalogError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Enter a valid repository URL."
            }
        }
    }
}

private struct RepositoryCard: View {
    let repository: RepositorySource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 60, height: 60)
                RepositoryIcon(urlString: repository.url, assetName: repository.iconName)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.05)
            }
            .frame(width: 60, height: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                Text(repository.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
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

private struct BrowsePage: View {
    @State private var topCovers: [Package] = []
    @State private var middleRandom: [Package] = []
    @State private var bottomIcons: [Package] = []
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 300, height: 160)
                                .overlay(
                                    Text(topCovers.indices.contains(i) ? topCovers[i].name : "")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .padding(8), alignment: .bottomLeading
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Featured Picks").font(.title2).padding(.horizontal, 12)

                    let gridCols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                    LazyVGrid(columns: gridCols, spacing: 12) {
                        ForEach(middleRandom) { pkg in
                            HStack(alignment: .center, spacing: 12) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.04))
                                    .frame(width: 44, height: 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pkg.name).font(.headline).lineLimit(1)
                                    if let v = pkg.version { Text(v).font(.caption).foregroundStyle(.secondary) }
                                }

                                Spacer()

                                Text("Install")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 12)
        }
        .onAppear {
            loadSamplePackages()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.showingDownloads = true
                } label: {
                    Label("Downloads", systemImage: "tray.and.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    appState.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private func loadSamplePackages() {
        let all = Persistence.loadAllPackages()
        let flat = all.flatMap { $0.packages }
        var shuffled = flat.shuffled()
        if shuffled.count > 4 {
            topCovers = Array(shuffled.prefix(4))
            shuffled.removeFirst(min(shuffled.count, 4))
        } else {
            topCovers = Array(shuffled.prefix(4))
            shuffled.removeAll()
        }
        middleRandom = Array(shuffled.prefix(10))
        shuffled.removeFirst(min(shuffled.count, middleRandom.count))
        bottomIcons = Array(shuffled.prefix(15))
    }
}

private struct Package: Identifiable, Codable {
    var id: UUID
    let name: String
    let version: String?
    let architecture: String?
    let description: String?
    let filename: String?
    let depends: String?

    init(id: UUID = UUID(), name: String, version: String? = nil, architecture: String? = nil, description: String? = nil, filename: String? = nil, depends: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.architecture = architecture
        self.description = description
        self.filename = filename
        self.depends = depends
    }
}

private enum Persistence {
    private static func cacheDir() -> URL? {
        do {
            let fm = FileManager.default
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let app = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Mochi")
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
            return app
        } catch {
            NSLog("[Persistence] failed to create cache dir: %@", String(describing: error))
            return nil
        }
    }

    private static func encodedFilename(for repositoryURL: String) -> String {
        let data = Data(repositoryURL.utf8)
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "=", with: "")
        return "packages_\(s).json"
    }

    struct PackageCacheFile: Codable {
        let repositoryURL: String
        let packages: [Package]
    }

    static func savePackages(_ packages: [Package], for repositoryURL: String) {
        guard let dir = cacheDir() else { return }
        let url = dir.appendingPathComponent(encodedFilename(for: repositoryURL))
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let payload = PackageCacheFile(repositoryURL: repositoryURL, packages: packages)
            let data = try enc.encode(payload)
            try data.write(to: url, options: .atomic)
            NSLog("[Persistence] saved %d packages to %@", packages.count, url.path)
        } catch {
            NSLog("[Persistence] save error: %@", String(describing: error))
        }
    }

    static func loadPackages(for repositoryURL: String) -> [Package]? {
        guard let dir = cacheDir() else { return nil }
        let url = dir.appendingPathComponent(encodedFilename(for: repositoryURL))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            let file = try dec.decode(PackageCacheFile.self, from: data)
            NSLog("[Persistence] loaded %d cached packages from %@", file.packages.count, url.path)
            return file.packages
        } catch {
            NSLog("[Persistence] load error: %@", String(describing: error))
            return nil
        }
    }

    static func loadAllPackages() -> [(repositoryURL: String, packages: [Package])] {
        guard let dir = cacheDir() else { return [] }
        var out: [(String, [Package])] = []
        let fm = FileManager.default
        do {
            let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for item in items where item.lastPathComponent.hasPrefix("packages_") {
                do {
                    let data = try Data(contentsOf: item)
                    let dec = JSONDecoder()
                    let file = try dec.decode(PackageCacheFile.self, from: data)
                    out.append((file.repositoryURL, file.packages))
                } catch {
                    NSLog("[Persistence] loadAll skip %@: %@", item.path, String(describing: error))
                }
            }
        } catch {
            NSLog("[Persistence] loadAll error: %@", String(describing: error))
        }
        return out
    }

    static func clearAllPackageCaches() {
        guard let dir = cacheDir() else { return }
        do {
            let fm = FileManager.default
            let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for item in items where item.lastPathComponent.hasPrefix("packages_") {
                try fm.removeItem(at: item)
                NSLog("[Persistence] removed cache %@", item.path)
            }
        } catch {
            NSLog("[Persistence] clear cache error: %@", String(describing: error))
        }
    }

    static func clearCache(for repositoryURL: String) {
        guard let dir = cacheDir() else { return }
        let name = encodedFilename(for: repositoryURL)
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                NSLog("[Persistence] removed cache for %@", repositoryURL)
            } catch {
                NSLog("[Persistence] clear cache error for %@: %@", repositoryURL, String(describing: error))
            }
        }
    }
}

private enum PackageCatalog {
    private static var platformIdentifier: String {
#if arch(arm64)
        return "darwin-arm64"
#else
        return "darwin-amd64"
#endif
    }
    static func load(from repositoryURL: String) async throws -> [Package] {
        guard let base = URL(string: repositoryURL) else { return [] }

        var candidates = ["Packages", "Packages.gz", "dists/./binary-amd64/Packages", "dists/./binary-arm64/Packages"]
        candidates.append(contentsOf: packageIndexCandidates())

        for c in candidates {
            let url = base.appendingPathComponent(c)
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    continue
                }

                var bodyData = data
                if c.hasSuffix(".gz") || isGzip(data: data) {
                    if let decompressed = try? decompressGzip(data: data) {
                        bodyData = decompressed
                    } else {
                        continue
                    }
                }

                if let text = String(data: bodyData, encoding: .utf8) {
                    let parsed = parsePackages(text: text)
                    let filtered = parsed.filter { matchesPlatform(architecture: $0.architecture) }
                    if !filtered.isEmpty {
                        await MainActor.run {
                            Persistence.savePackages(filtered, for: repositoryURL)
                        }
                        return filtered
                    }
                }
            } catch {
                continue
            }
        }

        if let base = URL(string: repositoryURL) {
            let fallback = await loadFromDirectoryListing(from: base)
            if !fallback.isEmpty { return fallback }
        }

        return []
    }

    private static func packageIndexCandidates() -> [String] {
        let distNames = [
            "big_sur",
            "iphoneos-arm64",
            "iphoneos-arm64-rootless",
            "appletvos-arm64",
            "watchos-arm",
            "watchos-arm64",
            "1800",
            "1900",
            "2000",
            "3000"
        ]
        let sections = ["main", "testing"]
        let architectures = ["darwin-amd64", "darwin-arm64"]

        var paths: [String] = []
        for dist in distNames {
            for section in sections {
                for architecture in architectures {
                    paths.append("dists/\(dist)/\(section)/binary-\(architecture)/Packages")
                }
            }
        }
        return paths
    }

    private static func matchesPlatform(architecture: String?) -> Bool {
        guard let architecture = architecture?.lowercased(), !architecture.isEmpty else { return true }
        if architecture == "all" { return true }
        if platformIdentifier.contains("arm64") {
            return architecture.contains("arm64") || architecture.contains("aarch64")
        } else {
            return architecture.contains("amd64") || architecture.contains("x86_64") || architecture.contains("i386")
        }
    }

    private static func loadFromDirectoryListing(from base: URL) async -> [Package] {
        do {
            NSLog("[PackageCatalog] scraping root: %@", base.absoluteString)
            let (data, response) = try await URLSession.shared.data(from: base)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("[PackageCatalog] root request failed: %@ -> %d", base.absoluteString, (response as? HTTPURLResponse)?.statusCode ?? -1)
                return []
            }
            guard let html = String(data: data, encoding: .utf8) else { return [] }

            func extractDebs(from htmlText: String, relativeTo urlBase: URL) -> [String] {
                let ns = htmlText as NSString
                var names: [String] = []

                let quotedPattern = #"<a[^>]+href=['"]([^'"]+\.deb)['"]"#
                if let re = try? NSRegularExpression(pattern: quotedPattern, options: .caseInsensitive) {
                    let matches = re.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length))
                    for m in matches {
                        if m.numberOfRanges >= 2 {
                            let href = ns.substring(with: m.range(at: 1))
                            let lastComponent = URL(string: href, relativeTo: urlBase)?.lastPathComponent ?? href
                            if lastComponent.lowercased().hasSuffix(".deb") {
                                names.append(lastComponent)
                            }
                        }
                    }
                }

                let unquotedPattern = #"<a[^>]+href=([^"'\s>]+\.deb)"#
                if let re2 = try? NSRegularExpression(pattern: unquotedPattern, options: .caseInsensitive) {
                    let matches = re2.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length))
                    for m in matches {
                        if m.numberOfRanges >= 2 {
                            let href = ns.substring(with: m.range(at: 1))
                            let lastComponent = URL(string: href, relativeTo: urlBase)?.lastPathComponent ?? href
                            if lastComponent.lowercased().hasSuffix(".deb") {
                                names.append(lastComponent)
                            }
                        }
                    }
                }

                let tokenPattern = #"([A-Za-z0-9._%+-]+\.deb)"#
                if let re3 = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) {
                    let matches = re3.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length))
                    for m in matches {
                        if m.numberOfRanges >= 2 {
                            let token = ns.substring(with: m.range(at: 1))
                            names.append(token)
                        }
                    }
                }

                return names
            }

            var names: [String] = []

            if !extractDebs(from: html, relativeTo: base).isEmpty {
                names.append(contentsOf: extractDebs(from: html, relativeTo: base))
                NSLog("[PackageCatalog] found %d .deb entries at root", names.count)
            }

            if names.isEmpty {
                var visited = Set<String>()
                var queue: [(URL, Int)] = [(base, 0)]
                let maxDepth = 3
                let maxRequests = 40
                var requests = 0

                while !queue.isEmpty && requests < maxRequests {
                    let (u, depth) = queue.removeFirst()
                    let key = u.absoluteString
                    if visited.contains(key) { continue }
                    visited.insert(key)
                    requests += 1

                    NSLog("[PackageCatalog] trying directory %@ (depth=%d)", u.absoluteString, depth)
                    do {
                        let (ddata, dresp) = try await URLSession.shared.data(from: u)
                        guard let dhttp = dresp as? HTTPURLResponse, dhttp.statusCode == 200 else { continue }
                        guard let dhtml = String(data: ddata, encoding: .utf8) else { continue }

                        let found = extractDebs(from: dhtml, relativeTo: u)
                        if !found.isEmpty {
                            NSLog("[PackageCatalog] found %d .debs in %@", found.count, u.absoluteString)
                            names.append(contentsOf: found)
                        }

                        if depth < maxDepth {
                            let dirPattern = #"<a[^>]+href=['"]([^'" ]+/)['"]"#
                            let dirRe = try? NSRegularExpression(pattern: dirPattern, options: .caseInsensitive)
                            let ns = dhtml as NSString
                            let dirMatches = dirRe?.matches(in: dhtml, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
                            for m in dirMatches {
                                if m.numberOfRanges >= 2 {
                                    let href = ns.substring(with: m.range(at: 1))
                                    if let durl = URL(string: href, relativeTo: u) {
                                        let normalized = durl.standardized
                                        if !visited.contains(normalized.absoluteString) {
                                            queue.append((normalized, depth + 1))
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        NSLog("[PackageCatalog] error fetching %@: %@", u.absoluteString, String(describing: error))
                        continue
                    }
                }
                NSLog("[PackageCatalog] BFS complete, checked %d URLs, found %d .deb names", requests, names.count)
            }

            if names.isEmpty {
                let candidates = ["pool/main/big_sur/", "pool/main/", "pool/"]
                for p in candidates {
                    if let purl = URL(string: p, relativeTo: base) {
                        NSLog("[PackageCatalog] probing common path %@", purl.absoluteString)
                        do {
                            let (pdata, presp) = try await URLSession.shared.data(from: purl)
                            if let http = presp as? HTTPURLResponse, http.statusCode == 200, let phtml = String(data: pdata, encoding: .utf8) {
                                let found = extractDebs(from: phtml, relativeTo: purl)
                                if !found.isEmpty {
                                    NSLog("[PackageCatalog] found %d .debs in %@", found.count, purl.absoluteString)
                                    names.append(contentsOf: found)
                                }
                            }
                        } catch {
                            NSLog("[PackageCatalog] probe %@ failed: %@", p, String(describing: error))
                            continue
                        }
                    }
                }
            }

            let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
            NSLog("[PackageCatalog] unique .deb filenames: %d", unique.count)
            let synthesized: [Package] = unique.compactMap { fname in
                let withoutExt = fname.replacingOccurrences(of: ".deb", with: "", options: .caseInsensitive)

                var parts = withoutExt.split(separator: "_")
                if parts.count >= 3 {
                    let archPart = parts.last.map(String.init) ?? ""
                    let version = String(parts[parts.count - 2])
                    let name = parts.dropLast(2).map(String.init).joined(separator: "_")
                    return Package(name: name, version: version, architecture: archPart, description: nil, filename: fname)
                }

                parts = withoutExt.split(separator: "-")
                if parts.count >= 3 {
                    let archPart = String(parts.last!)
                    let version = String(parts[parts.count - 2])
                    let name = parts.dropLast(2).map(String.init).joined(separator: "-")
                    return Package(name: name, version: version, architecture: archPart, description: nil, filename: fname)
                }

                parts = withoutExt.split(separator: "_")
                if parts.count == 2 {
                    return Package(name: String(parts[0]), version: String(parts[1]), architecture: nil, description: nil, filename: fname)
                }

                return nil
            }

            let filtered = synthesized.filter { matchesPlatform(architecture: $0.architecture) }

            NSLog("[PackageCatalog] synthesized %d packages, %d after platform filter", synthesized.count, filtered.count)
            if !filtered.isEmpty {
                Persistence.savePackages(filtered, for: base.absoluteString)
            }
            return filtered
        } catch {
            NSLog("[PackageCatalog] directory scraping error: %@", String(describing: error))
            return []
        }
    }

    private static func parsePackages(text: String) -> [Package] {
        text
            .components(separatedBy: "\n\n")
            .compactMap { block in
                var name: String?
                var version: String?
                var arch: String?
                var desc: String?
                var filename: String?
                var depends: String?

                for line in block.split(separator: "\n") {
                    let s = String(line)
                    if s.hasPrefix("Package:") {
                        name = value(after: "Package:", in: s)
                    } else if s.hasPrefix("Version:") {
                        version = value(after: "Version:", in: s)
                    } else if s.hasPrefix("Architecture:") {
                        arch = value(after: "Architecture:", in: s)
                    } else if s.hasPrefix("Description:") {
                        desc = value(after: "Description:", in: s)
                    } else if s.hasPrefix("Depends:") {
                        depends = value(after: "Depends:", in: s)
                    } else if s.hasPrefix("Filename:") {
                        filename = value(after: "Filename:", in: s)
                    }
                }

                if let name = name {
                    return Package(name: name, version: version, architecture: arch, description: desc, filename: filename, depends: depends)
                }
                return nil
            }
    }
    private static func isGzip(data: Data) -> Bool {
        return data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }

    private static func decompressGzip(data: Data) throws -> Data {
        let dstBufferSize = 4 * data.count + 64
        var dst = Data(count: dstBufferSize)
        let decompressed = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
            guard let dstBase = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                guard let srcBase = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                let outSize = compression_decode_buffer(dstBase, dstBufferSize, srcBase, data.count, nil, COMPRESSION_ZLIB)
                return outSize
            }
        }
        if decompressed > 0 {
            return dst.prefix(decompressed)
        }
        throw NSError(domain: "Decompress", code: 1, userInfo: nil)
    }
}

private struct PackageListView: View {
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

                                        Button(action: {
                                            InstallQueue.shared.enqueue(repository: repository.url, package: pkg, reason: "install")
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

        guard let version = pkg.version else {
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
                NSLog("[PackageListView] loaded dpkgInstalledPackages count=%d", dpkgInstalledPackages.count)
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
            NSLog("[PackageListView] installedPackageVersions count=%d", installedPackageVersions.count)
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

private struct SearchResult: Identifiable {
    let id: UUID
    let repo: String
    let pkg: Package
    init(repo: String, pkg: Package) {
        self.id = pkg.id
        self.repo = repo
        self.pkg = pkg
    }
}

private struct SearchPage: View {
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

                Group {
                    if results.isEmpty {
                        Group {
                            if query.isEmpty {
                                Text("Type to search cached packages")
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
                                                        NSLog("[SearchPage] install failed: %@", msg ?? "unknown")
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Downloads", systemImage: "tray.and.arrow.down")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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

private struct UpdateEntry: Identifiable {
    let id = UUID()
    let name: String
    let installedVersion: String
    let availableVersion: String
    let repository: String
    let package: Package
}

private struct UpdatesPage: View {
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Label("Downloads", systemImage: "tray.and.arrow.down")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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

private struct QueueEntry: Identifiable {
    enum Status { case pending, installing, succeeded, failed }
    let id = UUID()
    let repository: String
    let package: Package
    var reason: String
    var status: Status = .pending
    var message: String? = nil
    var missingDependencies: [String] = []
}

private class InstallQueue: ObservableObject {
    static let shared = InstallQueue()
    @Published private(set) var entries: [QueueEntry] = []

    private init() {}

    func enqueue(repository: String, package: Package, reason: String = "install") {
        var entry = QueueEntry(repository: repository, package: package, reason: reason)
        // quick dependency scan
        if let deps = package.depends {
            let names = deps.split(separator: ",").map { s -> String in
                let t = s.split(separator: "(").first.map(String.init) ?? String(s)
                return t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            var missing: [String] = []
            let all = Persistence.loadAllPackages()
            for n in names {
                let found = all.contains { _, pkgs in pkgs.contains(where: { $0.name.lowercased() == n }) }
                if !found { missing.append(n) }
            }
            entry.missingDependencies = missing
        }
        DispatchQueue.main.async {
            self.entries.append(entry)
            NotificationCenter.default.post(name: PackagesUpdatedNotification, object: nil)
        }
    }

    func remove(_ id: UUID) {
        DispatchQueue.main.async { self.entries.removeAll { $0.id == id } }
    }

    func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
    }

    func installAll() async {
        for idx in entries.indices {
            await withCheckedContinuation { cont in
                DispatchQueue.main.async { self.entries[idx].status = .installing; cont.resume() }
            }
            let entry = entries[idx]
            let (ok, msg) = await installPackageFromRepo(pkg: entry.package, repositoryURL: entry.repository)
            DispatchQueue.main.async {
                if ok {
                    self.entries[idx].status = .succeeded
                    self.entries[idx].message = msg
                } else {
                    self.entries[idx].status = .failed
                    self.entries[idx].message = msg
                }
            }
        }
    }
}

private struct DownloadsPage: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = InstallQueue.shared
    @State private var installingAll = false

    var body: some View {
        NavigationStack {
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
                                    Text(statusText(e.status))
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
                        else { Text("Install All") }
                    }
                    .disabled(queue.entries.isEmpty || installingAll)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func statusText(_ s: QueueEntry.Status) -> String {
        switch s {
        case .pending: return "Pending"
        case .installing: return "Installing"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }
}

fileprivate func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: [.numeric, .caseInsensitive, .forcedOrdering], range: nil, locale: .current)
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var errorMessage: String?

    let onSave: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "",
                    text: $sourceURL,
                    prompt: Text("https://apt.procurs.us/")
                )
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

private class RemoteImageLoader: ObservableObject {
    @Published var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    init(urlString: String, assetName: String) {
        if let cached = RemoteImageLoader.cache.object(forKey: urlString as NSString) {
            NSLog("[RemoteImageLoader] cache hit for %@", urlString)
            self.image = cached
            return
        }

        if assetName != "CydiaIcon", let local = NSImage(named: NSImage.Name(assetName)) {
            NSLog("[RemoteImageLoader] using local asset %@ for %@", assetName, urlString)
            RemoteImageLoader.cache.setObject(local, forKey: urlString as NSString)
            self.image = local
            return
        }

        var candidates: [URL] = []
        if let base = URL(string: urlString) {
            candidates.append(base.appendingPathComponent("CydiaIcon@3x.png"))
            candidates.append(base.appendingPathComponent("CydiaIcon.png"))
            candidates.append(base.appendingPathComponent("icon.png"))
            candidates.append(base.appendingPathComponent("favicon.ico"))
        }

        func tryNext(_ idx: Int) {
            if idx >= candidates.count {
                NSLog("[RemoteImageLoader] no icon found for %@, falling back to default asset", urlString)
                if let local = NSImage(named: NSImage.Name(assetName)) {
                    RemoteImageLoader.cache.setObject(local, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = local }
                    return
                }

                if let cydia = NSImage(named: NSImage.Name("CydiaIcon")) {
                    RemoteImageLoader.cache.setObject(cydia, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = cydia }
                    return
                }

                if let sys = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil) {
                    RemoteImageLoader.cache.setObject(sys, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = sys }
                }

                return
            }
            let url = candidates[idx]
            NSLog("[RemoteImageLoader] trying %@ for %@", url.absoluteString, urlString)
            let task = URLSession.shared.dataTask(with: url) { data, resp, err in
                if let err = err {
                    NSLog("[RemoteImageLoader] error fetching %@: %@", url.absoluteString, String(describing: err))
                    tryNext(idx + 1)
                    return
                }

                if let http = resp as? HTTPURLResponse {
                    if http.statusCode != 200 {
                        NSLog("[RemoteImageLoader] %@ returned HTTP %d", url.absoluteString, http.statusCode)
                        tryNext(idx + 1)
                        return
                    }
                }

                if let d = data, let ns = NSImage(data: d) {
                    NSLog("[RemoteImageLoader] loaded image from %@ (bytes=%d) for %@", url.absoluteString, d.count, urlString)
                    RemoteImageLoader.cache.setObject(ns, forKey: urlString as NSString)
                    DispatchQueue.main.async {
                        self.image = ns
                    }
                    return
                } else {
                    NSLog("[RemoteImageLoader] no image data at %@", url.absoluteString)
                    tryNext(idx + 1)
                }
            }
            task.resume()
        }

        tryNext(0)
    }
}

private struct RepositoryIcon: View {
    @StateObject private var loader: RemoteImageLoader

    init(urlString: String, assetName: String) {
        _loader = StateObject(wrappedValue: RemoteImageLoader(urlString: urlString, assetName: assetName))
    }

    var body: some View {
        Group {
            if let img = loader.image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.05)))
            } else {
                Image("CydiaIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.05)))
                    .opacity(0.9)
            }
        }
    }
}

struct ContentView: View {
    @State private var selection: Int = 1
    @State private var showingHelperInstallPrompt = false
    @State private var helperInstallMessage: String?
    @State private var showingHelperInstallAlert = false
    @StateObject private var appState = AppState()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                BrowsePage()
            }
            .tabItem {
                Label("Browse", systemImage: "square.grid.2x2")
            }
            .tag(0)

            NavigationStack {
                SourcesPage()
            }
            .tabItem {
                Label("Sources", systemImage: "tray.2")
            }
            .tag(1)

            NavigationStack {
                UpdatesPage()
            }
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(2)

            NavigationStack {
                SearchPage()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(3)
        }
        .frame(minWidth: 720, minHeight: 400)
        .environmentObject(appState)
        .sheet(isPresented: Binding(get: { appState.showingSettings }, set: { appState.showingSettings = $0 })) { SettingsView() }
        .sheet(isPresented: Binding(get: { appState.showingDownloads }, set: { appState.showingDownloads = $0 })) { DownloadsPage() }
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

#Preview {
    ContentView()
}
