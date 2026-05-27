import SwiftUI

#if os(tvOS)
@available(tvOS 15.0, *)
struct SearchPage_tvOS: View {
    @State private var query: String = ""

    @State private var results: [TVOSPackageResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search")
                .font(.largeTitle.bold())

            HStack {
                TextField("Search packages", text: $query)
                    .frame(maxWidth: 600)
                    .padding(8)
                    .background(Color.gray.opacity(0.18))
                    .cornerRadius(8)
                Button("Go") {
                    // no-op; live filtering below
                }
                .buttonStyle(.bordered)
            }

            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered = trimmedQuery.isEmpty ? [] : results.filter { r in
                let q = trimmedQuery
                if r.package.name.localizedCaseInsensitiveContains(q) { return true }
                if let desc = r.package.description, desc.localizedCaseInsensitiveContains(q) { return true }
                if let fn = r.package.filename, fn.localizedCaseInsensitiveContains(q) { return true }
                return false
            }
            // Use a List for proper tvOS focus & scrolling behavior
            if trimmedQuery.isEmpty {
                Spacer()
                Text("Type a package name to search")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { r in
                        NavigationLink {
                            TVOSPackageDetailView(result: r)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(r.package.name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if let v = r.package.version {
                                    Text(v)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let d = r.package.description {
                                    Text(d)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(TVOSPageBackground())
            .task {
            // load cached packages from persistence and flatten
            let all = Persistence.loadAllPackages()
            var out: [TVOSPackageResult] = []
            for (repoURL, pkgs) in all {
                for pkg in pkgs {
                    out.append(TVOSPackageResult(id: pkg.id, package: pkg, repositoryURL: repoURL))
                }
            }
            results = out
        }
    }
}

// top-level result model to avoid nested access-level issues
struct TVOSPackageResult: Identifiable {
    let id: UUID
    let package: Package
    let repositoryURL: String
}

@available(tvOS 15.0, *)
struct TVOSPackageDetailView: View {
    let result: TVOSPackageResult
    @State private var installing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: { dismiss() }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.bordered)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.package.name)
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .lineLimit(2)

                        if let v = result.package.version {
                            Text(v)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: { /* install placeholder */ }) {
                        if installing {
                            ProgressView()
                        } else {
                            Text("Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let d = result.package.description {
                    Text(d)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 18) {
                    detailCard(title: "Package", value: result.package.name)
                    detailCard(title: "Version", value: result.package.version ?? "No version")
                    detailCard(title: "Source", value: result.repositoryURL)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(36)
        }
        .background(TVOSPageBackground())
        .navigationTitle(result.package.name)
    }

    private func detailCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
#endif
