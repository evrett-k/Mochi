import Foundation

struct RootHelperClient {
    static func isHelperInstalled() -> Bool { false }

    static func bundledHelperURL() -> URL? { nil }

    static func bundledHelperExists() -> Bool { false }

    static func installBundledHelper() -> (Bool, String?) { (false, "Unsupported on iOS") }

    static func addRepository(url: String) -> (Bool, String?) { (false, "Unsupported on iOS") }

    static func installDeb(atPath path: String) -> (Bool, String?) { (false, "Unsupported on iOS") }

    static func removePackage(named packageName: String) -> (Bool, String?) { (false, "Unsupported on iOS") }
}
