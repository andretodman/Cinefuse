import XCTest
import CinefuseAppleCore
@testable import CinefuseMacApp

final class MacAppTests: XCTestCase {
    func testModelTokenShape() {
        let model = AppModel()
        model.userId = "usr_1"
        XCTAssertEqual(model.bearerToken, "user:usr_1")
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
