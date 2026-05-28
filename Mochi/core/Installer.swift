import Foundation

public func isCLIPresentSync(_ name: String) -> Bool {
#if os(macOS)
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
#else
    return false
#endif
}

public func bestFilenameMatch(in packages: [Package], targetName: String, targetVersion: String?, targetArch: String?) -> String? {
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

public func resolveFilenameFromRepository(pkg: Package, repositoryURL: String) async -> String? {
    let targetName = pkg.name.lowercased()
    let targetVersion = pkg.version?.lowercased()
    let targetArch = pkg.architecture?.lowercased()

    if let cachedPackages = Persistence.loadPackages(for: repositoryURL) {
        NSLog("[resolveFilenameFromRepository] checking packages for %@", pkg.name)
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

public func installPackageFromRepo(pkg: Package, repositoryURL: String) async -> (Bool, String?) {
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
