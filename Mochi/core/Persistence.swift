import Foundation

public enum Persistence {
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

    public struct PackageCacheFile: Codable {
        public let repositoryURL: String
        public let packages: [Package]
    }

    public static func savePackages(_ packages: [Package], for repositoryURL: String) {
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

    public static func loadPackages(for repositoryURL: String) -> [Package]? {
        guard let dir = cacheDir() else { return nil }
        let url = dir.appendingPathComponent(encodedFilename(for: repositoryURL))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            let file = try dec.decode(PackageCacheFile.self, from: data)
            NSLog("[Persistence] loaded %d packages from %@", file.packages.count, url.path)
            return file.packages
        } catch {
            NSLog("[Persistence] load error: %@", String(describing: error))
            return nil
        }
    }

    public static func loadAllPackages() -> [(repositoryURL: String, packages: [Package])] {
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

    public static func clearAllPackageCaches() {
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

    public static func clearCache(for repositoryURL: String) {
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
