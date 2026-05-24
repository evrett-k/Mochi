//
//  MochiApp.swift
//  Mochi
//
//  Created by michal on 5/21/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreServices

@main
struct MochiApp: App {
    init() {
        // No-op init. Previous attempt to set NSScroller.preferredScrollerStyle
        // caused a compile error because the property is get-only in this SDK.
        checkDefaultHandlerForDeb()
    }

    func checkDefaultHandlerForDeb() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let ut = UTType(filenameExtension: "deb")?.identifier else { return }
            let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mochi_test.deb")
            if let currentApp = NSWorkspace.shared.urlForApplication(toOpen: testURL) {
                let myApp = Bundle.main.bundleURL
                if currentApp != myApp {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Set Mochi as default for .deb files?"
                    alert.informativeText = "Another app is currently set to open .deb files. Set Mochi as the default handler?"
                    alert.addButton(withTitle: "Set as Default")
                    alert.addButton(withTitle: "Keep Current")
                    let resp = alert.runModal()
                    if resp == .alertFirstButtonReturn {
                        if let bundleId = Bundle.main.bundleIdentifier {
                            let status = LSSetDefaultRoleHandlerForContentType(ut as CFString, LSRolesMask.viewer, bundleId as CFString)
                            if status != noErr {
                                let fail = NSAlert()
                                fail.messageText = "Could not set Mochi as default"
                                fail.informativeText = "macOS prevented changing the default handler. You can change it manually in Finder > Get Info > Open with."
                                fail.runModal()
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if #available(macOS 13.0, *) {
                ContentView()
            } else {
                LegacyContentView()
            }
        }
    }
}
