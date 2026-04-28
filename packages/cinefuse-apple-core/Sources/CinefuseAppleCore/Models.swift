import Foundation
import Observation

public struct Project: Codable, Identifiable {
    public let id: String
    public let ownerUserId: String
    public let title: String
    public let logline: String
    public let targetDurationMinutes: Int
    public let tone: String
    public let currentPhase: String
}

public struct ListProjectsResponse: Codable {
    public let projects: [Project]
}

public struct CreateProjectResponse: Codable {
    public let project: Project
}

public struct Shot: Codable, Identifiable {
    public let id: String
    public let projectId: String
    public let prompt: String
    public let modelTier: String
    public let status: String
    public let clipUrl: String?
    public let orderIndex: Int?
    public let durationSec: Int?
    public let thumbnailUrl: String?
    public let audioRefs: [String]?
    public let characterLocks: [String]?
}

public struct StoryScene: Codable, Identifiable {
    public let id: String
    public let projectId: String
    public let orderIndex: Int
    public let title: String
    public let description: String
    public let mood: String
}

public struct ListScenesResponse: Codable {
    public let scenes: [StoryScene]
}

public struct CreateSceneResponse: Codable {
    public let scene: StoryScene
}

public struct GenerateStoryboardResponse: Codable {
    public let projectId: String
    public let scenes: [StoryScene]
}

public struct ListShotsResponse: Codable {
    public let shots: [Shot]
}

public struct CreateShotResponse: Codable {
    public let shot: Shot
}

public struct CharacterProfile: Codable, Identifiable {
    public let id: String
    public let projectId: String
    public let name: String
    public let description: String
    public let status: String
    public let previewUrl: String?
    public let consistencyScore: Double?
    public let consistencyThreshold: Double?
    public let consistencyPassed: Bool?
}

public struct ListCharactersResponse: Codable {
    public let characters: [CharacterProfile]
}

public struct CreateCharacterResponse: Codable {
    public let character: CharacterProfile
}

public struct AudioTrack: Codable, Identifiable {
    public let id: String
    public let projectId: String
    public let shotId: String?
    public let kind: String
    public let title: String
    public let sourceUrl: String?
    public let waveformUrl: String?
    public let laneIndex: Int
    public let startMs: Int
    public let durationMs: Int
    public let status: String
}

public struct ListAudioTracksResponse: Codable {
    public let audioTracks: [AudioTrack]
}

public struct CreateAudioTrackResponse: Codable {
    public let audioTrack: AudioTrack
}

public struct TimelineResponse: Codable {
    public let projectId: String
    public let shots: [Shot]
    public let audioTracks: [AudioTrack]
}

public struct ShotQuote: Codable {
    public let sparksCost: Int
    public let modelTier: String
    public let modelId: String
    public let estimatedDurationSec: Int?
}

public struct QuoteShotResponse: Codable {
    public let quote: ShotQuote
}

public struct Job: Codable, Identifiable {
    public let id: String
    public let projectId: String
    public let shotId: String?
    public let kind: String
    public let status: String
    public let progressPct: Int?
    public let costToUsCents: Int
    public let promptText: String?
    public let modelId: String?
    public let errorMessage: String?
    public let outputUrl: String?
    public let updatedAt: String?
}

public struct ListJobsResponse: Codable {
    public let jobs: [Job]
}

public struct CreateJobResponse: Codable {
    public let job: Job
}

public struct StitchResult: Codable {
    public let id: String
    public let kind: String
    public let status: String
    public let stitchedUrl: String?
    public let durationSec: Int?
    public let costToUsCents: Int
}

public struct StitchOperationResponse: Codable {
    public let stitch: StitchResult
    public let job: Job
}

public struct GenerateShotResponse: Codable {
    public let shot: Shot
    public let job: Job
    public let quote: ShotQuote
}

public struct BalanceResponse: Codable {
    public let userId: String
    public let balance: Int
}

public struct ProjectEvent: Codable {
    public let type: String
    public let projectId: String
    public let shotId: String?
    public let jobId: String?
    public let status: String?
    public let progressPct: Int?
    public let timestamp: String
}

@Observable
public final class AppModel {
    private static let storedUserIdKey = "cinefuse.auth.userId"
    private static let storedUserEmailKey = "cinefuse.auth.userEmail"
    private static let storedDisplayNameKey = "cinefuse.auth.displayName"
    private static let storedPubfuseAccessTokenKey = "cinefuse.auth.pubfuseAccessToken"
    private let userDefaults: UserDefaults

    public var userId: String = ""
    public var userEmail: String = ""
    public var userDisplayName: String = ""
    public var pubfuseAccessToken: String = ""
    public var isAuthenticated = false
    public var projects: [Project] = []
    public var balance: Int = 0
    public var isLoading = false
    public var errorMessage: String?

    public var bearerToken: String {
        if shouldUsePubfuseAccessTokenForSelectedServer,
           !pubfuseAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pubfuseAccessToken
        }
        return legacyBearerToken
    }

    public var legacyBearerToken: String {
        "user:\(userId)"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        restoreSession()
    }

    public func signIn(userId: String) {
        let normalized = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userId = normalized
        self.userEmail = ""
        self.userDisplayName = ""
        self.pubfuseAccessToken = ""
        self.isAuthenticated = !normalized.isEmpty
        if isAuthenticated {
            userDefaults.set(normalized, forKey: Self.storedUserIdKey)
            userDefaults.removeObject(forKey: Self.storedUserEmailKey)
            userDefaults.removeObject(forKey: Self.storedDisplayNameKey)
            userDefaults.removeObject(forKey: Self.storedPubfuseAccessTokenKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedUserIdKey)
            userDefaults.removeObject(forKey: Self.storedUserEmailKey)
            userDefaults.removeObject(forKey: Self.storedDisplayNameKey)
            userDefaults.removeObject(forKey: Self.storedPubfuseAccessTokenKey)
        }
    }

    public func signInPubfuse(userId: String, accessToken: String, email: String?, displayName: String?) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        self.userId = normalizedUserId
        self.userEmail = normalizedEmail
        self.userDisplayName = normalizedDisplayName
        self.pubfuseAccessToken = normalizedAccessToken
        self.isAuthenticated = !normalizedUserId.isEmpty

        if isAuthenticated {
            userDefaults.set(normalizedUserId, forKey: Self.storedUserIdKey)
            userDefaults.set(normalizedEmail, forKey: Self.storedUserEmailKey)
            userDefaults.set(normalizedDisplayName, forKey: Self.storedDisplayNameKey)
            userDefaults.set(normalizedAccessToken, forKey: Self.storedPubfuseAccessTokenKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedUserIdKey)
            userDefaults.removeObject(forKey: Self.storedUserEmailKey)
            userDefaults.removeObject(forKey: Self.storedDisplayNameKey)
            userDefaults.removeObject(forKey: Self.storedPubfuseAccessTokenKey)
        }
    }

    public func signOut() {
        userId = ""
        userEmail = ""
        userDisplayName = ""
        pubfuseAccessToken = ""
        isAuthenticated = false
        projects = []
        balance = 0
        isLoading = false
        errorMessage = nil
        userDefaults.removeObject(forKey: Self.storedUserIdKey)
        userDefaults.removeObject(forKey: Self.storedUserEmailKey)
        userDefaults.removeObject(forKey: Self.storedDisplayNameKey)
        userDefaults.removeObject(forKey: Self.storedPubfuseAccessTokenKey)
    }

    public func restoreSession() {
        let stored = (userDefaults.string(forKey: Self.storedUserIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedEmail = (userDefaults.string(forKey: Self.storedUserEmailKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDisplayName = (userDefaults.string(forKey: Self.storedDisplayNameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedAccessToken = (userDefaults.string(forKey: Self.storedPubfuseAccessTokenKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        userId = stored
        userEmail = storedEmail
        userDisplayName = storedDisplayName
        pubfuseAccessToken = storedAccessToken
        isAuthenticated = !stored.isEmpty
    }

    private var shouldUsePubfuseAccessTokenForSelectedServer: Bool {
        let selectedServerMode = (userDefaults.string(forKey: "cinefuse.server.mode") ?? "local")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch selectedServerMode {
        case "production":
            return true
        case "custom":
            let customURL = (userDefaults.string(forKey: "cinefuse.server.customBaseURL") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if customURL.contains("localhost") || customURL.contains("127.0.0.1") {
                return false
            }
            return !customURL.isEmpty
        default:
            return false
        }
    }
}

@Observable
public final class EditorSettingsModel {
    private static let showTooltipsKey = "cinefuse.editor.showTooltips"
    private static let restoreLastOpenWorkspaceKey = "cinefuse.editor.restoreLastOpenWorkspace"
    private let userDefaults: UserDefaults

    public var showTooltips: Bool {
        didSet {
            userDefaults.set(showTooltips, forKey: Self.showTooltipsKey)
        }
    }
    public var restoreLastOpenWorkspace: Bool {
        didSet {
            userDefaults.set(restoreLastOpenWorkspace, forKey: Self.restoreLastOpenWorkspaceKey)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.showTooltipsKey) == nil {
            self.showTooltips = true
            userDefaults.set(true, forKey: Self.showTooltipsKey)
        } else {
            self.showTooltips = userDefaults.bool(forKey: Self.showTooltipsKey)
        }
        if userDefaults.object(forKey: Self.restoreLastOpenWorkspaceKey) == nil {
            self.restoreLastOpenWorkspace = true
            userDefaults.set(true, forKey: Self.restoreLastOpenWorkspaceKey)
        } else {
            self.restoreLastOpenWorkspace = userDefaults.bool(forKey: Self.restoreLastOpenWorkspaceKey)
        }
    }
}
