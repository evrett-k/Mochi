import Foundation
import Combine
import SwiftUI

public struct QueueEntry: Identifiable {
    public enum Status { case pending, installing, succeeded, failed }
    public let id = UUID()
    public let repository: String
    public let package: Package
    public var reason: String
    public var status: Status = .pending
    public var message: String? = nil
    public var missingDependencies: [String] = []

    public init(repository: String, package: Package, reason: String = "install") {
        self.repository = repository
        self.package = package
        self.reason = reason
    }
}

public class InstallQueue: ObservableObject {
    public static let shared = InstallQueue()
    @Published public private(set) var entries: [QueueEntry] = []

    private init() {}

    private func log(_ message: String, enabled: Bool, handler: ((String) -> Void)? = nil) {
        guard enabled else { return }
        handler?(message)
        NSLog("[Queue] %@", message)
    }

    public func enqueue(repository: String, package: Package, reason: String = "install") {
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

    public func remove(_ id: UUID) {
        DispatchQueue.main.async { self.entries.removeAll { $0.id == id } }
    }

    public func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
    }

    public func installAll(debugLogging: Bool = false, logHandler: ((String) -> Void)? = nil) async {
        log("installAll start count=\(entries.count)", enabled: debugLogging, handler: logHandler)
        for idx in entries.indices {
            await withCheckedContinuation { cont in
                DispatchQueue.main.async { self.entries[idx].status = .installing; cont.resume() }
            }
            let entry = entries[idx]
            log("processing \(entry.package.name) reason=\(entry.reason) repo=\(entry.repository)", enabled: debugLogging, handler: logHandler)
            if entry.reason.lowercased().contains("remove") || entry.reason.lowercased().contains("uninstall") {
#if os(macOS)
                let (ok, msg) = await withCheckedContinuation { (cont: CheckedContinuation<(Bool,String?), Never>) in
                    DispatchQueue.global().async {
                        let res = RootHelperClient.removePackage(named: entry.package.name)
                        cont.resume(returning: res)
                    }
                }
#else
                let ok = false
                let msg: String? = "Unsupported on this platform"
#endif
                log("uninstall \(entry.package.name) ok=\(ok) msg=\(msg ?? "nil")", enabled: debugLogging, handler: logHandler)
                DispatchQueue.main.async {
                    if ok {
                        self.entries[idx].status = .succeeded
                        self.entries[idx].message = msg
                    } else {
                        self.entries[idx].status = .failed
                        self.entries[idx].message = msg
                    }
                }
            } else {
                let (ok, msg) = await installPackageFromRepo(pkg: entry.package, repositoryURL: entry.repository)
                log("install \(entry.package.name) ok=\(ok) msg=\(msg ?? "nil")", enabled: debugLogging, handler: logHandler)
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
        log("installAll finished", enabled: debugLogging, handler: logHandler)
    }
}
