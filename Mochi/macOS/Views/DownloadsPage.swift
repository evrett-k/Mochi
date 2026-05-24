import SwiftUI

@available(macOS 13.0, *)
struct DownloadsPage: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = InstallQueue.shared
    @State private var installingAll = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if queue.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No queued downloads")
                            .font(.headline)
                        Text("Queue packages or updates from Sources, Search, or Updates, then install them in order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                } else {
                    List {
                        ForEach(queue.entries) { e in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.package.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(e.repository)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if !e.missingDependencies.isEmpty {
                                        Text("Missing deps: " + e.missingDependencies.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(statusText(e))
                                        .font(.caption)
                                        .foregroundStyle(e.status == .failed ? .red : .secondary)
                                    if let message = e.message, !message.isEmpty {
                                        Text(message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Button(action: {
                                    InstallQueue.shared.remove(e.id)
                                }) {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Remove from queue")
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.primary.opacity(0.03))
                        }
                        .onDelete { idx in
                            for i in idx { InstallQueue.shared.remove(queue.entries[i].id) }
                        }
                    }
                    .listStyle(.plain)
                }

                let hasActive = queue.entries.contains { $0.status == .pending || $0.status == .installing }

                if hasActive {
                    HStack(spacing: 10) {
                        Button("Clear") { InstallQueue.shared.clear() }
                        Spacer()
                        Button(action: {
                            installingAll = true
                            Task {
                                await InstallQueue.shared.installAll()
                                installingAll = false
                            }
                        }) {
                            if installingAll { ProgressView().controlSize(.small) }
                            else { Text("Complete Actions") }
                        }
                        .disabled(installingAll)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func statusText(_ e: QueueEntry) -> String {
        switch e.status {
        case .pending:
            let action = e.reason.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if action.contains("install") { return "Pending install" }
            if action.contains("remov") || action.contains("uninstall") { return "Pending uninstall" }
            if action.contains("update") { return "Pending update" }
            if action.isEmpty { return "Pending" }
            return "Pending \(action)"
        case .installing: return "Installing"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }
}
