import SwiftUI
import AppKit
import Combine

func gridColumns(for width: CGFloat) -> [GridItem] {
    let count: Int
    if width >= 1100 {
        count = 3
    } else if width >= 720 {
        count = 2
    } else {
        count = 1
    }
    return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
}

func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: [.numeric, .caseInsensitive, .forcedOrdering], range: nil, locale: .current)
}

private struct RemoteImageCache {
    static let shared = NSCache<NSString, NSImage>()
}

final class RemoteImageLoader: ObservableObject {
    @Published var image: NSImage?

    init(urlString: String, assetName: String) {
        if let cached = RemoteImageCache.shared.object(forKey: urlString as NSString) {
            self.image = cached
            return
        }

        if assetName != "CydiaIcon", let local = NSImage(named: NSImage.Name(assetName)) {
            RemoteImageCache.shared.setObject(local, forKey: urlString as NSString)
            self.image = local
            return
        }

        var candidates: [URL] = []
        if let base = URL(string: urlString) {
            candidates.append(base.appendingPathComponent("CydiaIcon@3x.png"))
            candidates.append(base.appendingPathComponent("CydiaIcon.png"))
            candidates.append(base.appendingPathComponent("icon.png"))
            candidates.append(base.appendingPathComponent("favicon.ico"))
        }

        func tryNext(_ idx: Int) {
            if idx >= candidates.count {
                if let local = NSImage(named: NSImage.Name(assetName)) {
                    RemoteImageCache.shared.setObject(local, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = local }
                    return
                }

                if let cydia = NSImage(named: NSImage.Name("CydiaIcon")) {
                    RemoteImageCache.shared.setObject(cydia, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = cydia }
                    return
                }

                if let sys = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil) {
                    RemoteImageCache.shared.setObject(sys, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = sys }
                }
                return
            }

            let url = candidates[idx]
            URLSession.shared.dataTask(with: url) { data, resp, err in
                if err != nil {
                    tryNext(idx + 1)
                    return
                }

                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    tryNext(idx + 1)
                    return
                }

                if let d = data, let ns = NSImage(data: d) {
                    RemoteImageCache.shared.setObject(ns, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = ns }
                } else {
                    tryNext(idx + 1)
                }
            }.resume()
        }

        tryNext(0)
    }
}

struct RepositoryIcon: View {
    @StateObject private var loader: RemoteImageLoader

    init(urlString: String, assetName: String) {
        _loader = StateObject(wrappedValue: RemoteImageLoader(urlString: urlString, assetName: assetName))
    }

    var body: some View {
        Group {
            if let img = loader.image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.05)))
            } else {
                Image("CydiaIcon")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.05)))
                    .opacity(0.9)
            }
        }
    }
}
