import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct WatchSearchView: View {
    @State private var query: String = ""
    @State private var results: [(repo: String, pkg: Package)] = []
    @State private var showingNoCache = false

    var body: some View {
        VStack {
            TextField("Search", text: $query)
                .onChange(of: query) { _ in performSearch() }

            if results.isEmpty {
                Text(query.isEmpty ? "Enter a query" : "No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                List {
                    ForEach(results, id: \.pkg.id) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.pkg.name).font(.headline)
                                if let v = item.pkg.version { Text(v).font(.caption) }
                            }
                            Spacer()
                            Button {
                                InstallQueue.shared.enqueue(repository: item.repo, package: item.pkg, reason: "install")
                            } label: {
                                Image(systemName: "tray.and.arrow.down")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { performSearch() }
    }

    private func performSearch() {
        let all = Persistence.loadAllPackages()
        guard !all.isEmpty else { results = []; showingNoCache = true; return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { results = []; showingNoCache = false; return }

        var out: [(String, Package)] = []
        for (repo, pkgs) in all {
            for p in pkgs {
                if p.name.lowercased().contains(q) || (p.description?.lowercased().contains(q) ?? false) || (p.version?.lowercased().contains(q) ?? false) {
                    out.append((repo, p))
                }
            }
        }
        results = out
    }
}
#endif
