import SwiftUI

@main
struct CinefuseMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 520)
        }
    }
}
