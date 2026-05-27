//
//  MochiApp.swift
//  Mochi
//
//  Created by michal on 5/21/26.
//

import SwiftUI
#if os(macOS)
import AppKit
import CoreServices
#elseif os(iOS)
import UIKit
#elseif os(tvOS)
import UIKit
#endif
import UniformTypeIdentifiers

@main
struct MochiApp: App {
    #if os(iOS)
    private var forceIPadRoot: Bool {
        ProcessInfo.processInfo.arguments.contains("--mochi-force-ipad-root")
    }
    #endif

    init() {
        #if os(tvOS)
        UITableView.appearance().backgroundColor = .clear
        UIScrollView.appearance().backgroundColor = .clear
        #endif
        #if os(macOS)
        checkDefaultHandlerForDeb()
        #endif
    }

    #if os(macOS)
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
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            if #available(iOS 16.0, *) {
                if forceIPadRoot || UIDevice.current.userInterfaceIdiom == .pad {
                    ContentView_iPadOS()
                } else {
                    ContentView_iOS()
                }
            } else {
                if forceIPadRoot || UIDevice.current.userInterfaceIdiom == .pad {
                    LegacyContentView_iPadOS()
                } else {
                    LegacyContentView_iOS()
                }
            }
            #elseif os(watchOS)
            if #available(watchOS 9.0, *) {
                ContentView_watchOS()
            } else {
                Text("WatchOS 9 required")
            }
            #elseif os(tvOS)
            if #available(tvOS 15.0, *) {
                ContentView_tvOS()
            } else {
                Text("tvOS 15 required")
            }
            #elseif os(macOS)
            if #available(macOS 13.0, *) {
                ContentView()
            } else {
                LegacyContentView()
            }
            #else
            Text("Unsupported platform")
            #endif
        }
    }
}
