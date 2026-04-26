import SwiftUI
import CinefuseAppleCore

@main
struct CinefuseMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            CinefuseRootView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 520)
        }
    }
}
