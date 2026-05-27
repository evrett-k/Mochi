import SwiftUI

#if os(tvOS)
@available(tvOS 15.0, *)
struct BrowsePage_tvOS: View {
    var body: some View {
        TVOSPageBackground()
    }
}
#endif
