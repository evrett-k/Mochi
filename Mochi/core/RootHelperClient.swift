import Foundation

#if os(macOS)
struct RootHelperClient {
    static let helperPath = "/usr/local/bin/RootHelper"

    static func isHelperInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }

    static func bundledHelperURL() -> URL? {
        if let url = Bundle.main.url(forResource: "RootHelper", withExtension: nil) {
            return url
        }
        let bundleURL = Bundle.main.bundleURL
        let candidate = bundleURL.appendingPathComponent("Contents/Resources/RootHelper")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static func bundledHelperExists() -> Bool {
        bundledHelperURL() != nil
    }

    static func installBundledHelper() -> (Bool, String?) {
        guard let src = bundledHelperURL()?.path else {
            return (false, "Bundled helper not found in app resources")
        }
        let cmd = "install -m 0755 '\(src)' '\(helperPath)' && chown root:wheel '\(helperPath)' && chmod 4755 '\(helperPath)'"
        let appleScript = "do shell script \"\(cmd)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return (false, "Failed to launch elevation prompt: \(error.localizedDescription)")
        }

        proc.waitUntilExit()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if proc.terminationStatus == 0 {
            return (true, nil)
        } else {
            return (false, err ?? "Installer exited with code \(proc.terminationStatus)")
        }
    }

    static func addRepository(url: String) -> (Bool, String?) {
        guard isHelperInstalled() else {
            return (false, "Helper not installed at \(helperPath)")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: helperPath)
        proc.arguments = [url]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return (false, "Failed to launch helper: \(error.localizedDescription)")
        }

        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if proc.terminationStatus == 0 {
            return (true, nil)
        } else {
            return (false, err ?? out ?? "Unknown error (exit \(proc.terminationStatus))")
        }
    }

    static func installDeb(atPath path: String) -> (Bool, String?) {
        return installDebDirectly(atPath: path)
    }

    static func removePackage(named packageName: String) -> (Bool, String?) {
        guard let dpkgPath = locateDpkgPath() else {
            return (false, "Could not locate dpkg under /opt/procursus")
        }

        let procursusPath = [
            "/opt/procursus/bin",
            "/opt/procursus/usr/bin",
            "/opt/procursus/sbin",
            "/opt/procursus/usr/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        let shellCommand = "env PATH=\"\(procursusPath)\" \"\(dpkgPath)\" -r \(shellQuoted(packageName))"
        let appleScript = "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return (false, "Failed to launch elevation prompt: \(error.localizedDescription)")
        }

        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if proc.terminationStatus == 0 {
            return (true, nil)
        }

        return (false, err ?? out ?? "Uninstaller exited with code \(proc.terminationStatus)")
    }

    private static func installDebDirectly(atPath path: String) -> (Bool, String?) {
        guard let dpkgPath = locateDpkgPath() else {
            return (false, "Could not locate dpkg under /opt/procursus")
        }

        let procursusPath = [
            "/opt/procursus/bin",
            "/opt/procursus/usr/bin",
            "/opt/procursus/sbin",
            "/opt/procursus/usr/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        let shellCommand = "env PATH=\"\(procursusPath)\" \"\(dpkgPath)\" -i \(shellQuoted(path))"
        let appleScript = "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return (false, "Failed to launch elevation prompt: \(error.localizedDescription)")
        }

        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if proc.terminationStatus == 0 {
            return (true, nil)
        }

        return (false, err ?? out ?? "Installer exited with code \(proc.terminationStatus)")
    }

    private static func locateDpkgPath() -> String? {
        let candidates = [
            "/opt/procursus/bin/dpkg",
            "/opt/procursus/usr/bin/dpkg",
            "/opt/procursus/sbin/dpkg",
            "/usr/bin/dpkg"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
#else
struct RootHelperClient {
    static func isHelperInstalled() -> Bool { false }

    static func bundledHelperURL() -> URL? { nil }

    static func bundledHelperExists() -> Bool { false }

    static func installBundledHelper() -> (Bool, String?) { (false, "Unsupported on this platform") }

    static func addRepository(url: String) -> (Bool, String?) { (false, "Unsupported on this platform") }

    static func installDeb(atPath path: String) -> (Bool, String?) { (false, "Unsupported on this platform") }

    static func removePackage(named packageName: String) -> (Bool, String?) { (false, "Unsupported on this platform") }
}
#endif
