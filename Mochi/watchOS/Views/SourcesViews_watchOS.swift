import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct WatchSourcesView: View {
    @State private var repositories: [RepositorySource] = RepositoryCatalog.load()

    var body: some View {
        List {
            ForEach(repositories, id: \.url) { repo in
                NavigationLink(destination: WatchPackageListView(repositoryURL: repo.url)) {
                    VStack(alignment: .leading) {
                        Text(repo.name).font(.headline)
                        Text(repo.url).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
#endif
