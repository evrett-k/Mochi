import Foundation

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
}
