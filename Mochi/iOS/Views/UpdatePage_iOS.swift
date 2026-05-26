import SwiftUI

@available(iOS 16.0, *)
struct UpdatePage_iOS: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
            }
            .navigationTitle("Updates")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.showingDownloads = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct UpdatePage_iOS_Previews: PreviewProvider {
    static var previews: some View {
        UpdatePage_iOS().environmentObject(AppState())
    }
}
