import SwiftUI
import Combine

#if os(watchOS)
final class AppState: ObservableObject {
    @Published var showingDownloads: Bool = false
    @Published var showingSettings: Bool = false
}
#endif