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
    public let costToUsCents: Int
}

public struct ListJobsResponse: Codable {
    public let jobs: [Job]
}

public struct CreateJobResponse: Codable {
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
    public let timestamp: String
}

@Observable
public final class AppModel {
    private static let storedUserIdKey = "cinefuse.auth.userId"
    private let userDefaults: UserDefaults

    public var userId: String = ""
    public var isAuthenticated = false
    public var projects: [Project] = []
    public var balance: Int = 0
    public var isLoading = false
    public var errorMessage: String?

    public var bearerToken: String {
        "user:\(userId)"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        restoreSession()
    }

    public func signIn(userId: String) {
        let normalized = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userId = normalized
        self.isAuthenticated = !normalized.isEmpty
        if isAuthenticated {
            userDefaults.set(normalized, forKey: Self.storedUserIdKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedUserIdKey)
        }
    }

    public func signOut() {
        userId = ""
        isAuthenticated = false
        projects = []
        balance = 0
        isLoading = false
        errorMessage = nil
        userDefaults.removeObject(forKey: Self.storedUserIdKey)
    }

    public func restoreSession() {
        let stored = (userDefaults.string(forKey: Self.storedUserIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        userId = stored
        isAuthenticated = !stored.isEmpty
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
