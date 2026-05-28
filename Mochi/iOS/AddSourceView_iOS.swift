import SwiftUI

#if os(iOS)
@available(iOS 16.0, *)
struct AddSourceView_iOS: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL = ""
    @State private var errorMessage: String?

    let onSave: (Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("", text: $sourceURL, prompt: Text("https://apt.procurs.us/"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                HStack {
                    Spacer()
                    Button("Cancel") {
                        onSave(false)
                        dismiss()
                    }
                    Button("Add") {
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
        }
    }
}

@available(iOS 16.0, *)
struct AddSourceView_iOS_Previews: PreviewProvider {
    static var previews: some View {
        AddSourceView_iOS { _ in }
    }
}
#endif
