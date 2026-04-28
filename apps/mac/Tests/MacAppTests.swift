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

    func testPubfuseSessionPersistenceAndRestore() {
        let suiteName = "cinefuse.tests.pubfuse-session.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppModel(userDefaults: defaults)
        first.signInPubfuse(
            userId: "usr_pubfuse_1",
            accessToken: "jwt-token",
            email: "creator@pubfuse.com",
            displayName: "Creator One"
        )
        XCTAssertTrue(first.isAuthenticated)
        XCTAssertEqual(first.userEmail, "creator@pubfuse.com")
        XCTAssertEqual(first.userDisplayName, "Creator One")

        let restored = AppModel(userDefaults: defaults)
        XCTAssertEqual(restored.userId, "usr_pubfuse_1")
        XCTAssertEqual(restored.userEmail, "creator@pubfuse.com")
        XCTAssertEqual(restored.userDisplayName, "Creator One")
        XCTAssertEqual(restored.pubfuseAccessToken, "jwt-token")
    }

    func testEditorSettingsTooltipsDefaultAndPersistence() {
        let suiteName = "cinefuse.tests.settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = EditorSettingsModel(userDefaults: defaults)
        XCTAssertEqual(first.showTooltips, true)
        XCTAssertEqual(first.restoreLastOpenWorkspace, true)

        first.showTooltips = false
        first.restoreLastOpenWorkspace = false
        let second = EditorSettingsModel(userDefaults: defaults)
        XCTAssertEqual(second.showTooltips, false)
        XCTAssertEqual(second.restoreLastOpenWorkspace, false)
    }

    func testThumbnailFileNameIsDeterministicAndSanitized() async throws {
        let store = GeneratedFilesStore()
        let fileName = await store.thumbnailFileName(
            clipName: "Wide / Opening: Shot",
            shotId: "shot:01",
            orderIndex: 3
        )
        XCTAssertEqual(fileName, "Wide---Opening--Shot-3-shot-01.jpg")
    }

    func testWriteThumbnailDataCreatesResolvableFile() async throws {
        let store = GeneratedFilesStore()
        let projectId = "thumb-test-\(UUID().uuidString)"
        let shotId = "shot-\(UUID().uuidString)"
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9]) // minimal JPEG markers

        let writtenURL = try await store.writeThumbnailData(
            payload,
            projectId: projectId,
            clipName: "Hero Clip",
            shotId: shotId,
            orderIndex: 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: writtenURL.path))

        let resolved = try await store.existingThumbnailURL(
            projectId: projectId,
            clipName: "Hero Clip",
            shotId: shotId,
            orderIndex: 1
        )
        XCTAssertEqual(resolved?.path, writtenURL.path)
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
