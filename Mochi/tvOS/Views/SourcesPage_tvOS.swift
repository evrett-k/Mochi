import SwiftUI

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
@available(tvOS 15.0, *)
struct SourcesPage_tvOS: View {
    private let repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        ZStack {
            TVOSPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        Text("Sources")
                            .font(.largeTitle.bold())

                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 24)], spacing: 24) {
                        ForEach(repositories) { repository in
                            NavigationLink {
                                TVOSRepositoryDetailView(repository: repository)
                            } label: {
                                TVOSRepositoryCard(repository: repository)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}

@available(tvOS 15.0, *)
struct TVOSRepositoryCard: View {
    let repository: RepositorySource

    @State private var isFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RepositoryIcon_tvOS(urlString: repository.url, assetName: repository.iconName)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 8) {
                Text(repository.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(repository.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
        )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(color: Color.black.opacity(isFocused ? 0.35 : 0.12), radius: isFocused ? 12 : 4, x: 0, y: isFocused ? 8 : 2)
            .focusable(true) { focused in
                withAnimation(.easeInOut(duration: 0.12)) { isFocused = focused }
            }
    }
}

@available(tvOS 15.0, *)
struct TVOSRepositoryDetailView: View {
    let repository: RepositorySource
    @State private var packages: [Package] = []
    @State private var loading = false
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading packages…")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(packages) { pkg in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pkg.name)
                                    .font(.headline)
                                Text(pkg.version ?? "No version")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.thinMaterial)
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(repository.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .task(id: repository.url) {
            await loadPackages()
        }
    }

    private func loadPackages() async {
        loading = true
        defer { loading = false }
        do {
            packages = try await PackageCatalog.load(from: repository.url)
        } catch {
            packages = []
        }
    }
}
#endif
