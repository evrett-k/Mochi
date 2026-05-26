import SwiftUI

#if os(watchOS)
@available(watchOS 9.0, *)
struct ContentView_watchOS: View {
    var body: some View {
        // Minimal root view for isolating startup crashes
        Text("Mochi")
    }
}
#endif
