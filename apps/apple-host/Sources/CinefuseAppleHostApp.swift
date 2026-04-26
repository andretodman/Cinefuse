import SwiftUI
import CinefuseAppleCore

@main
struct CinefuseAppleHostApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            CinefuseRootView()
                .environment(model)
        }
    }
}
