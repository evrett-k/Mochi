import SwiftUI

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var errorMessage: String?

    let onSave: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "",
                    text: $sourceURL,
                    prompt: Text("https://apt.procurs.us/")
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

                HStack {
                    Spacer()

                    Button("Cancel") {
                        onSave(false)
                        dismiss()
                    }

                    Button("Add") {
                        if RootHelperClient.isHelperInstalled() {
                            let (success, message) = RootHelperClient.addRepository(url: sourceURL)
                            if success {
                                errorMessage = nil
                                Persistence.clearCache(for: sourceURL)
                                onSave(true)
                                dismiss()
                            } else {
                                errorMessage = message ?? "Unknown helper error"
                                onSave(false)
                            }
                        } else {
                            do {
                                try RepositoryCatalog.save(sourceURL: sourceURL)
                                errorMessage = nil
                                Persistence.clearCache(for: sourceURL)
                                onSave(true)
                                dismiss()
                            } catch {
                                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                errorMessage = msg
                                onSave(false)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceURL.isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Source")
            .padding(20)
            .frame(minWidth: 360, minHeight: 160)
        }
    }
}
