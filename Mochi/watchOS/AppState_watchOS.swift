import SwiftUI
import Combine

#if os(watchOS)
final class AppState: ObservableObject {
    @Published var showingDownloads: Bool = false
    @Published var showingSettings: Bool = false
}
#endif

// Lightweight installer stub for watchOS — real installation isn't supported on watch
public func installPackageFromRepo(pkg: Package, repositoryURL: String) async -> (Bool, String?) {
    return (false, "install not supported on watchOS")
}
