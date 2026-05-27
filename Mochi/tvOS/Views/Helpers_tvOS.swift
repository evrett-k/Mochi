import SwiftUI
import Combine

#if os(tvOS)
import UIKit

private final class RemoteImageCache_tvOS {
    static let shared = NSCache<NSString, UIImage>()
}

final class RemoteImageLoader_tvOS: ObservableObject {
    @Published var image: UIImage?

    init(urlString: String, assetName: String) {
        if let cached = RemoteImageCache_tvOS.shared.object(forKey: urlString as NSString) {
            self.image = cached
            return
        }

        if assetName != "CydiaIcon", let local = UIImage(named: assetName) {
            RemoteImageCache_tvOS.shared.setObject(local, forKey: urlString as NSString)
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
                if let local = UIImage(named: assetName) {
                    RemoteImageCache_tvOS.shared.setObject(local, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = local }
                    return
                }

                if let sys = UIImage(systemName: "archivebox.fill") {
                    RemoteImageCache_tvOS.shared.setObject(sys, forKey: urlString as NSString)
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

                if let d = data, let ui = UIImage(data: d) {
                    RemoteImageCache_tvOS.shared.setObject(ui, forKey: urlString as NSString)
                    DispatchQueue.main.async { self.image = ui }
                } else {
                    tryNext(idx + 1)
                }
            }.resume()
        }

        tryNext(0)
    }
}

struct RepositoryIcon_tvOS: View {
    @StateObject private var loader: RemoteImageLoader_tvOS

    init(urlString: String, assetName: String) {
        _loader = StateObject(wrappedValue: RemoteImageLoader_tvOS(urlString: urlString, assetName: assetName))
    }

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
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

#endif
