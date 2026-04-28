import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("CinefuseAppleCore_CinefuseAppleCore.bundle").path
        let buildPath = "/Users/atodman/Documents/GitHub/Cinefuse/packages/cinefuse-apple-core/.build/arm64-apple-macosx/debug/CinefuseAppleCore_CinefuseAppleCore.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}