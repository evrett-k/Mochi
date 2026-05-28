import Foundation

// SimulatorConnector: when running in simulators for iOS, tvOS, or watchOS,
// attempt to locate repository data on the host macOS and expose the host
// sources list path so the app can reuse host-managed repo lists/caches.

#if os(iOS) || os(tvOS) || os(watchOS)
public enum SimulatorConnector {
    /// If running in a simulator and the host exposes a path to the repo sources,
    /// return a URL to that host file. Returns nil otherwise.
    public static func hostSourcesFileURL() -> URL? {
        #if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        if let hostHome = env["SIMULATOR_HOST_HOME"] {
            let candidate = URL(fileURLWithPath: hostHome).appendingPathComponent("opt/procursus/etc/apt/sources.list.d/procursus.sources")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // As a fallback, check the host-root /opt path — on some setups the
        // simulator process can see host /opt directly.
        let direct = URL(fileURLWithPath: "/opt/procursus/etc/apt/sources.list.d/procursus.sources")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        #endif
        return nil
    }
}
#endif
