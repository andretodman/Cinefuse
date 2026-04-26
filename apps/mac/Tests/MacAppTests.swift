import XCTest
import CinefuseAppleCore
@testable import CinefuseMacApp

final class MacAppTests: XCTestCase {
    func testModelTokenShape() {
        let model = AppModel()
        model.userId = "usr_1"
        XCTAssertEqual(model.bearerToken, "user:usr_1")
    }

    func testSessionPersistenceAndRestore() {
        let suiteName = "cinefuse.tests.session.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppModel(userDefaults: defaults)
        first.signIn(userId: "usr_saved_1")
        XCTAssertTrue(first.isAuthenticated)

        let restored = AppModel(userDefaults: defaults)
        XCTAssertEqual(restored.userId, "usr_saved_1")
        XCTAssertTrue(restored.isAuthenticated)

        restored.signOut()
        let empty = AppModel(userDefaults: defaults)
        XCTAssertFalse(empty.isAuthenticated)
        XCTAssertEqual(empty.userId, "")
    }
}

final class MacAppContractTests: XCTestCase {
    func testAPIClientUsesDefaultBaseURL() {
        let client = APIClient(baseURLString: "http://localhost:4000")
        XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:4000")
    }

    func testAPIClientUsesCanonicalCinefusePrefix() {
        XCTAssertEqual(APIClient.cinefusePrefix, "/api/v1/cinefuse")
    }
}
