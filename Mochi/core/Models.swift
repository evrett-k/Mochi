import Foundation
import Compression
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public let PackagesUpdatedNotification = Notification.Name("PackagesUpdated")

public func value(after prefix: String, in line: String) -> String? {
    guard line.hasPrefix(prefix) else { return nil }
    let start = line.index(line.startIndex, offsetBy: prefix.count)
    return line[start...].trimmingCharacters(in: .whitespaces)
}

public func loadDpkgInstalledPackagesGlobal() -> [String: String] {
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

public struct Package: Identifiable, Codable {
    public var id: UUID
    public let name: String
    public let version: String?
    public let architecture: String?
    public let description: String?
    public let filename: String?
    public let depends: String?

    public init(id: UUID = UUID(), name: String, version: String? = nil, architecture: String? = nil, description: String? = nil, filename: String? = nil, depends: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.architecture = architecture
        self.description = description
        self.filename = filename
        self.depends = depends
    }
}

public struct RepositorySource: Identifiable {
    public let id = UUID()
    public let name: String
    public let url: String
    public let iconName: String
}

#if os(iOS) || os(tvOS) || os(watchOS)
private enum SimulatorConnectorFallback {
    static func hostSourcesFileURL() -> URL? {
        #if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        if let hostHome = env["SIMULATOR_HOST_HOME"] {
            let candidate = URL(fileURLWithPath: hostHome).appendingPathComponent("opt/procursus/etc/apt/sources.list.d/procursus.sources")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let direct = URL(fileURLWithPath: "/opt/procursus/etc/apt/sources.list.d/procursus.sources")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        #endif
        return nil
    }
}
#endif

public enum RepositoryCatalog {
    private static var sourcesFileURL: URL {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if let host = SimulatorConnectorFallback.hostSourcesFileURL() {
            return host
        }
        #endif
        return URL(fileURLWithPath: "/opt/procursus/etc/apt/sources.list.d/procursus.sources")
    }

    public static func load() -> [RepositorySource] {
        guard let contents = try? String(contentsOf: sourcesFileURL, encoding: .utf8) else {
            return [fallbackRepository]
        }

        let repositories = parse(contents: contents)
        return repositories.isEmpty ? [fallbackRepository] : repositories
    }

    public static func save(sourceURL: String) throws {
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
#if os(macOS)
            if NSImage(named: NSImage.Name(c)) != nil {
                return c
            }
#else
            if UIImage(named: c) != nil {
                return c
            }
#endif
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

public enum PackageCatalog {
    private static var platformIdentifier: String {
#if arch(arm64)
        return "darwin-arm64"
#else
        return "darwin-amd64"
#endif
    }

    public static func load(from repositoryURL: String) async throws -> [Package] {
        guard let base = URL(string: repositoryURL) else { return [] }

        var candidates = ["Packages", "Packages.gz", "dists/./binary-amd64/Packages", "dists/./binary-arm64/Packages"]
        candidates.append(contentsOf: packageIndexCandidates())

        for candidate in candidates {
            let url = base.appendingPathComponent(candidate)
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    continue
                }

                var bodyData = data
                if candidate.hasSuffix(".gz") || isGzip(data: data) {
                    guard let decompressed = try? decompressGzip(data: data) else { continue }
                    bodyData = decompressed
                }

                guard let text = String(data: bodyData, encoding: .utf8) else { continue }
                let parsed = parsePackages(text: text)
                let filtered = parsed.filter { matchesPlatform(architecture: $0.architecture) }
                if !filtered.isEmpty {
                    await MainActor.run {
                        Persistence.savePackages(filtered, for: repositoryURL)
                    }
                    return filtered
                }
            } catch {
                continue
            }
        }

        let fallback = await loadFromDirectoryListing(from: base)
        if !fallback.isEmpty {
            return fallback
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

                let quotedPattern = #"<a[^>]+href=['\"]([^'\"]+\.deb)['\"]"#
                if let re = try? NSRegularExpression(pattern: quotedPattern, options: .caseInsensitive) {
                    for match in re.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length)) {
                        guard match.numberOfRanges >= 2 else { continue }
                        let href = ns.substring(with: match.range(at: 1))
                        let lastComponent = URL(string: href, relativeTo: urlBase)?.lastPathComponent ?? href
                        if lastComponent.lowercased().hasSuffix(".deb") {
                            names.append(lastComponent)
                        }
                    }
                }

                let unquotedPattern = #"<a[^>]+href=([^"'\s>]+\.deb)"#
                if let re2 = try? NSRegularExpression(pattern: unquotedPattern, options: .caseInsensitive) {
                    for match in re2.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length)) {
                        guard match.numberOfRanges >= 2 else { continue }
                        let href = ns.substring(with: match.range(at: 1))
                        let lastComponent = URL(string: href, relativeTo: urlBase)?.lastPathComponent ?? href
                        if lastComponent.lowercased().hasSuffix(".deb") {
                            names.append(lastComponent)
                        }
                    }
                }

                let tokenPattern = #"([A-Za-z0-9._%+-]+\.deb)"#
                if let re3 = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) {
                    for match in re3.matches(in: htmlText, options: [], range: NSRange(location: 0, length: ns.length)) {
                        guard match.numberOfRanges >= 2 else { continue }
                        names.append(ns.substring(with: match.range(at: 1)))
                    }
                }

                return names
            }

            var names: [String] = []

            let rootMatches = extractDebs(from: html, relativeTo: base)
            if !rootMatches.isEmpty {
                names.append(contentsOf: rootMatches)
                NSLog("[PackageCatalog] found %d .deb entries at root", names.count)
            }

            if names.isEmpty {
                var visited = Set<String>()
                var queue: [(URL, Int)] = [(base, 0)]
                let maxDepth = 3
                let maxRequests = 40
                var requests = 0

                while !queue.isEmpty && requests < maxRequests {
                    let (url, depth) = queue.removeFirst()
                    let key = url.absoluteString
                    if visited.contains(key) { continue }
                    visited.insert(key)
                    requests += 1

                    NSLog("[PackageCatalog] trying directory %@ (depth=%d)", url.absoluteString, depth)
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                        guard let html = String(data: data, encoding: .utf8) else { continue }

                        let found = extractDebs(from: html, relativeTo: url)
                        if !found.isEmpty {
                            NSLog("[PackageCatalog] found %d .debs in %@", found.count, url.absoluteString)
                            names.append(contentsOf: found)
                        }

                        if depth < maxDepth {
                            let dirPattern = #"<a[^>]+href=['\"]([^'" ]+/)['\"]"#
                            let dirRe = try? NSRegularExpression(pattern: dirPattern, options: .caseInsensitive)
                            let htmlNSString = html as NSString
                            let dirMatches = dirRe?.matches(in: html, options: [], range: NSRange(location: 0, length: htmlNSString.length)) ?? []
                            for match in dirMatches {
                                guard match.numberOfRanges >= 2 else { continue }
                                let href = htmlNSString.substring(with: match.range(at: 1))
                                if let childURL = URL(string: href, relativeTo: url) {
                                    let normalized = childURL.standardized
                                    if !visited.contains(normalized.absoluteString) {
                                        queue.append((normalized, depth + 1))
                                    }
                                }
                            }
                        }
                    } catch {
                        NSLog("[PackageCatalog] error fetching %@: %@", url.absoluteString, String(describing: error))
                    }
                }

                NSLog("[PackageCatalog] BFS complete, checked %d URLs, found %d .deb names", requests, names.count)
            }

            if names.isEmpty {
                let candidates = ["pool/main/big_sur/", "pool/main/", "pool/"]
                for candidate in candidates {
                    guard let probeURL = URL(string: candidate, relativeTo: base) else { continue }
                    NSLog("[PackageCatalog] probing common path %@", probeURL.absoluteString)
                    do {
                        let (data, response) = try await URLSession.shared.data(from: probeURL)
                        if let http = response as? HTTPURLResponse, http.statusCode == 200,
                           let html = String(data: data, encoding: .utf8) {
                            let found = extractDebs(from: html, relativeTo: probeURL)
                            if !found.isEmpty {
                                NSLog("[PackageCatalog] found %d .debs in %@", found.count, probeURL.absoluteString)
                                names.append(contentsOf: found)
                            }
                        }
                    } catch {
                        NSLog("[PackageCatalog] probe %@ failed: %@", candidate, String(describing: error))
                    }
                }
            }

            let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
            NSLog("[PackageCatalog] unique .deb filenames: %d", unique.count)
            let synthesized: [Package] = unique.compactMap { filename in
                let withoutExt = filename.replacingOccurrences(of: ".deb", with: "", options: .caseInsensitive)

                var parts = withoutExt.split(separator: "_")
                if parts.count >= 3 {
                    let architecture = parts.last.map(String.init) ?? ""
                    let version = String(parts[parts.count - 2])
                    let name = parts.dropLast(2).map(String.init).joined(separator: "_")
                    return Package(name: name, version: version, architecture: architecture, description: nil, filename: filename)
                }

                parts = withoutExt.split(separator: "-")
                if parts.count >= 3 {
                    let architecture = String(parts.last!)
                    let version = String(parts[parts.count - 2])
                    let name = parts.dropLast(2).map(String.init).joined(separator: "-")
                    return Package(name: name, version: version, architecture: architecture, description: nil, filename: filename)
                }

                parts = withoutExt.split(separator: "_")
                if parts.count == 2 {
                    return Package(name: String(parts[0]), version: String(parts[1]), architecture: nil, description: nil, filename: filename)
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
                var architecture: String?
                var description: String?
                var filename: String?
                var depends: String?

                for line in block.split(separator: "\n") {
                    let lineText = String(line)
                    if lineText.hasPrefix("Package:") {
                        name = value(after: "Package:", in: lineText)
                    } else if lineText.hasPrefix("Version:") {
                        version = value(after: "Version:", in: lineText)
                    } else if lineText.hasPrefix("Architecture:") {
                        architecture = value(after: "Architecture:", in: lineText)
                    } else if lineText.hasPrefix("Description:") {
                        description = value(after: "Description:", in: lineText)
                    } else if lineText.hasPrefix("Depends:") {
                        depends = value(after: "Depends:", in: lineText)
                    } else if lineText.hasPrefix("Filename:") {
                        filename = value(after: "Filename:", in: lineText)
                    }
                }

                if let name = name {
                    return Package(name: name, version: version, architecture: architecture, description: description, filename: filename, depends: depends)
                }
                return nil
            }
    }

    private static func isGzip(data: Data) -> Bool {
        return data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }

    private static func decompressGzip(data: Data) throws -> Data {
        let destinationBufferSize = 4 * data.count + 64
        var destination = Data(count: destinationBufferSize)
        let decompressedSize = destination.withUnsafeMutableBytes { destinationPtr -> Int in
            guard let destinationBase = destinationPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return data.withUnsafeBytes { sourcePtr -> Int in
                guard let sourceBase = sourcePtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                return compression_decode_buffer(destinationBase, destinationBufferSize, sourceBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }

        if decompressedSize > 0 {
            return destination.prefix(decompressedSize)
        }
        throw NSError(domain: "Decompress", code: 1, userInfo: nil)
    }
}
