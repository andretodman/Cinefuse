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

/// Top-level editor mode: video storyboard + shots vs audio-first DAW workflow.
public enum CreationMode: String, CaseIterable, Identifiable, Sendable {
    case video
    case audio

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
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

/// Maps artifact URLs to something AVFoundation can open without custom HTTP headers.
/// Gateway `GET …/api/v1/cinefuse/projects/{id}/files/{fileId}` requires Bearer auth; use a synced local copy for playback.
public enum CinefusePlaybackURLResolver {
    public static func resolveForPlayback(
        remoteURLString: String?,
        localRecords: [String: LocalFileRecord],
        fileManager: FileManager = .default
    ) -> URL? {
        guard let raw = remoteURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let u = URL(string: raw), u.isFileURL {
            return fileManager.fileExists(atPath: u.path) ? u : nil
        }
        if let record = localRecords[raw],
           record.status == .synced || record.status == .alreadyPresent,
           let path = record.localPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        let pathLower = url.path.lowercased()
        if pathLower.contains("/api/v1/cinefuse/projects/"), pathLower.contains("/files/") {
            return nil
        }
        return url
    }
}

extension Shot {
    /// Local file or public URL suitable for ``AVPlayer`` / ``NSWorkspace``; nil while gateway project-file URLs are unsynced (they require Bearer auth).
    public func playbackURL(localRecords: [String: LocalFileRecord]) -> URL? {
        CinefusePlaybackURLResolver.resolveForPlayback(remoteURLString: clipUrl, localRecords: localRecords)
    }

    /// Returns a copy with `clipUrl` replaced (e.g. local `file://` override for uploaded-preview playback).
    public func withClipUrl(_ clipUrl: String?) -> Shot {
        Shot(
            id: id,
            projectId: projectId,
            prompt: prompt,
            modelTier: modelTier,
            status: status,
            clipUrl: clipUrl,
            orderIndex: orderIndex,
            durationSec: durationSec,
            thumbnailUrl: thumbnailUrl,
            audioRefs: audioRefs,
            characterLocks: characterLocks
        )
    }

    /// Shots that participate in the sound timeline and audio preview: linked `audioRefs`, an audio lane with a source URL scoped to this shot, **or** a generated audio artifact on `clipUrl` (score/dialogue/SFX with no lane row yet).
    public func hasSoundContent(audioTracks: [AudioTrack]) -> Bool {
        if let refs = audioRefs, !refs.isEmpty {
            return true
        }
        if audioTracks.contains(where: { track in
            guard track.shotId == id else { return false }
            guard let url = track.sourceUrl else { return false }
            return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return true
        }
        let clip = clipUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clip.isEmpty else { return false }
        return Self.clipUrlLikelyAudioArtifact(clip)
    }

    /// Same as ``hasSoundContent`` plus: synced local file under `clipUrl` looks like audio (covers API URL quirks and manifest-only proof).
    /// Pass ``audioJobs`` so sound-generation rows stay visible when ``clipUrl`` is a gateway `/files/{id}` URL with no extension (``clipUrlLikelyAudioArtifact`` false) and before sync completes.
    public func qualifiesForAudioModeLists(
        audioTracks: [AudioTrack],
        syncedLocalRecords: [String: LocalFileRecord],
        audioJobs: [Job] = []
    ) -> Bool {
        if hasSoundContent(audioTracks: audioTracks) {
            return true
        }
        if Self.shotHasEligibleAudioPipelineJob(jobs: audioJobs, shotId: id) {
            return true
        }
        guard let clip = clipUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            return false
        }
        guard let record = syncedLocalRecords[clip],
              record.status == .synced || record.status == .alreadyPresent,
              let path = record.localPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return false
        }
        let lower = path.lowercased()
        return [".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg"].contains { lower.hasSuffix($0) }
    }

    /// Non-failed ``kind == "audio"`` jobs for this shot keep the sound row on the timeline while URLs lack audio-looking paths.
    private static func shotHasEligibleAudioPipelineJob(jobs: [Job], shotId: String) -> Bool {
        jobs.contains { job in
            guard job.shotId == shotId, job.kind == "audio" else { return false }
            let s = job.status.lowercased()
            return s != "failed" && s != "cancelled"
        }
    }

    /// True when `clipUrl` points at an audio file (generated sound pipeline) vs video.
    private static func clipUrlLikelyAudioArtifact(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        if lower.contains("/audio/") {
            return true
        }
        // Strip query/fragment so `…/take.wav?sig=1` still matches `.wav`.
        let pathOnly = lower.split(separator: "?").first.map(String.init) ?? lower
        let pathNoHash = pathOnly.split(separator: "#").first.map(String.init) ?? pathOnly
        if [".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg"].contains(where: { pathNoHash.hasSuffix($0) }) {
            return true
        }
        // Common API path segments without relying on `/audio/` prefix.
        if pathNoHash.contains("/score/") || pathNoHash.contains("/dialogue/")
            || pathNoHash.contains("/sfx/") || pathNoHash.contains("/mix/")
            || pathNoHash.contains("/lipsync/") {
            return true
        }
        return false
    }
}

// MARK: - Sound blueprints (audio creation)

public struct SoundBlueprint: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let projectId: String
    public let name: String
    public let templateId: String?
    public let referenceFileIds: [String]

    public init(id: String, projectId: String, name: String, templateId: String?, referenceFileIds: [String]) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.templateId = templateId
        self.referenceFileIds = referenceFileIds
    }
}

public struct ListSoundBlueprintsResponse: Codable, Sendable {
    public let soundBlueprints: [SoundBlueprint]
}

public struct CreateSoundBlueprintRequest: Codable, Sendable {
    public let name: String
    public let templateId: String?
    public let referenceFileIds: [String]

    public init(name: String, templateId: String?, referenceFileIds: [String]) {
        self.name = name
        self.templateId = templateId
        self.referenceFileIds = referenceFileIds
    }
}

public struct CreateSoundBlueprintResponse: Codable, Sendable {
    public let soundBlueprint: SoundBlueprint
}

/// Response from `POST .../projects/:id/files` after uploading reference bytes (staging until Pubfuse Files IDs are wired).
public struct UploadProjectFileAPIResponse: Codable, Sendable {
    public let file: UploadedProjectFileRef
}

public struct UploadedProjectFileRef: Codable, Sendable {
    public let id: String
    public let filename: String?
    public let byteSize: Int?
}

public struct AudioMixExportResponse: Codable {
    public let job: Job
    public let export: AudioMixExportArtifact
}

public struct AudioMixExportArtifact: Codable, Sendable {
    public let fileUrl: String?
    public let sparksCost: Int?
    public let costToUsCents: Int?
}

public struct CreateAudioTrackResponse: Codable {
    public let audioTrack: AudioTrack
}

/// Response from POST `/audio/dialogue`, `/audio/score`, `/audio/sfx`, `/audio/mix`, `/audio/lipsync`.
public struct AudioGenerationAPIResponse: Codable {
    public let audioTrack: AudioTrack?
    public let job: Job
    public let sparksCost: Int?
    public let skipped: Bool?
    public let skippedFeature: String?
    public let featureError: JobFeatureError?
    public let providerAdapter: String?
}

public struct JobFeatureError: Codable, Sendable, Hashable {
    public let provider: String?
    public let reason: String?
    public let detail: String?
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
    public let requestId: String?
    public let idempotencyKey: String?
    public let invokeState: String?
    public let falEndpoint: String?
    public let falStatusUrl: String?
    /// Music / non-fal providers (e.g. ElevenLabs compose URL); falls back to `falEndpoint` in UI when nil.
    public let providerEndpoint: String?
    public let providerStatusCode: Int?
    public let providerResponseSnippet: String?
    /// When true, the MCP marked this audio feature as skipped (provider limitation); overall flow continues.
    public let skippedFeature: Bool?
    public let featureError: JobFeatureError?
    public let providerAdapter: String?
    /// Whether a downloadable artifact URL was produced for this job (when applicable).
    public let outputCreated: Bool?
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
