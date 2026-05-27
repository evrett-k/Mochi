import SwiftUI
import Combine

#if os(tvOS)
final class AppState: ObservableObject {
    @Published var showingDownloads: Bool = false
    @Published var showingSettings: Bool = false
}

// tvOS installer stub removed — rely on core Installer implementation when available
#endif
