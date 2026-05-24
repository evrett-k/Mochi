import SwiftUI
import Combine

final class AppState: ObservableObject {
    @Published var showingDownloads: Bool = false
    @Published var showingSettings: Bool = false
}
