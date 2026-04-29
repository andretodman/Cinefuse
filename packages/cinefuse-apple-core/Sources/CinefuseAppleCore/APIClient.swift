import Foundation

public enum CinefuseAPIErrorUserInfoKey {
    public static let errorCode = "cinefuse.error.code"
    public static let currentStatus = "cinefuse.error.currentStatus"
}

public struct PubfuseAuthUser: Codable {
    public let id: String
    public let username: String?
    public let email: String?
    public let displayName: String?
    public let firstName: String?
    public let lastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName
        case firstName
        case lastName
    }

    public var resolvedDisplayName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            return fullName
        }
        if let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        return id
    }
}

public struct PubfuseAuthResponse: Codable {
    public let token: String
    public let user: PubfuseAuthUser
}

public struct APIClient {
    public let baseURL: URL
    public static let cinefusePrefix = "/api/v1/cinefuse"

    public init(baseURLString: String = ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000") {
        self.baseURL = URL(string: baseURLString)!
    }

    public func healthCheck() async -> Bool {
        func check(path: String) async -> Bool {
            var request = URLRequest(url: buildURL(path: path))
            request.httpMethod = "GET"
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return false
                }
                return (200..<300).contains(http.statusCode)
            } catch {
                return false
            }
        }

        if await check(path: "\(Self.cinefusePrefix)/health") {
            return true
        }
        return await check(path: "/health")
    }

    public func loginPubfuse(authBaseURLString: String, email: String, password: String) async throws -> PubfuseAuthResponse {
        struct LoginRequest: Encodable {
            let email: String
            let password: String
        }
        let authBaseURL = URL(string: authBaseURLString) ?? baseURL
        var request = URLRequest(url: buildURL(baseURL: authBaseURL, path: "/api/users/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuth(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PubfuseAuthResponse.self, from: data)
    }

    public func signupPubfuse(
        authBaseURLString: String,
        username: String,
        email: String,
        password: String,
        displayName: String
    ) async throws -> PubfuseAuthResponse {
        struct SignupRequest: Encodable {
            let username: String
            let email: String
            let password: String
            let displayName: String
        }
        let authBaseURL = URL(string: authBaseURLString) ?? baseURL
        var request = URLRequest(url: buildURL(baseURL: authBaseURL, path: "/api/users/signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SignupRequest(
                username: username,
                email: email,
                password: password,
                displayName: displayName
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuth(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PubfuseAuthResponse.self, from: data)
    }

    public func requestPubfusePasswordReset(authBaseURLString: String, email: String) async throws {
        struct ForgotPasswordRequest: Encodable {
            let email: String
        }
        let authBaseURL = URL(string: authBaseURLString) ?? baseURL
        var request = URLRequest(url: buildURL(baseURL: authBaseURL, path: "/api/forgot-password"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ForgotPasswordRequest(email: email))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuth(response: response, data: data)
    }

    public func resetPubfusePassword(authBaseURLString: String, token: String, newPassword: String) async throws {
        struct ResetPasswordRequest: Encodable {
            let token: String
            let password: String
        }

        let authBaseURL = URL(string: authBaseURLString) ?? baseURL
        var request = URLRequest(url: buildURL(baseURL: authBaseURL, path: "/api/reset-password"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ResetPasswordRequest(token: token, password: newPassword)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateAuth(response: response, data: data)
    }

    public func listProjects(token: String) async throws -> [Project] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListProjectsResponse.self, from: data).projects
    }

    public func createProject(token: String, title: String) async throws -> Project {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateProjectResponse.self, from: data).project
    }

    public func deleteProject(token: String, projectId: String) async throws {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    public func renameProject(token: String, projectId: String, title: String) async throws -> Project {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateProjectResponse.self, from: data).project
    }

    public func listShots(token: String, projectId: String) async throws -> [Shot] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListShotsResponse.self, from: data).shots
    }

    public func listTimeline(token: String, projectId: String) async throws -> TimelineResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/timeline"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await performDataRequest(request, context: "listTimeline")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TimelineResponse.self, from: data)
    }

    public func reorderTimelineShots(token: String, projectId: String, shotIds: [String]) async throws -> [Shot] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/timeline/reorder"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["shotIds": shotIds])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListShotsResponse.self, from: data).shots
    }

    public func listAudioTracks(token: String, projectId: String) async throws -> [AudioTrack] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio-tracks"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListAudioTracksResponse.self, from: data).audioTracks
    }

    public func listSoundBlueprints(token: String, projectId: String) async throws -> [SoundBlueprint] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/sound-blueprints"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListSoundBlueprintsResponse.self, from: data).soundBlueprints
    }

    public func createSoundBlueprint(token: String, projectId: String, body: CreateSoundBlueprintRequest) async throws -> SoundBlueprint {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/sound-blueprints"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateSoundBlueprintResponse.self, from: data).soundBlueprint
    }

    public func exportAudioMix(token: String, projectId: String, idempotencyKey: String? = nil) async throws -> AudioMixExportResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/export/audio-mix"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = AudioMixExportRequestBody(idempotencyKey: idempotencyKey ?? "export-audio-mix:\(projectId)")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioMixExportResponse.self, from: data)
    }

    public func createAudioTrack(
        token: String,
        projectId: String,
        kind: String,
        title: String,
        shotId: String? = nil,
        laneIndex: Int = 0,
        startMs: Int = 0,
        durationMs: Int = 0
    ) async throws -> AudioTrack {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio-tracks"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "kind": AnyEncodable(kind),
            "title": AnyEncodable(title),
            "shotId": AnyEncodable(shotId),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
    }

    public func generateDialogue(
        token: String,
        projectId: String,
        shotId: String?,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioGenerationAPIResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio/dialogue"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "shotId": AnyEncodable(shotId),
            "title": AnyEncodable(title),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioGenerationAPIResponse.self, from: data)
    }

    public func generateScore(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioGenerationAPIResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio/score"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "title": AnyEncodable(title),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioGenerationAPIResponse.self, from: data)
    }

    public func generateSFX(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioGenerationAPIResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio/sfx"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "title": AnyEncodable(title),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioGenerationAPIResponse.self, from: data)
    }

    public func mixAudio(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioGenerationAPIResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio/mix"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "title": AnyEncodable(title),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioGenerationAPIResponse.self, from: data)
    }

    public func lipsyncAudio(
        token: String,
        projectId: String,
        shotId: String?,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioGenerationAPIResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/audio/lipsync"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "shotId": AnyEncodable(shotId),
            "title": AnyEncodable(title),
            "laneIndex": AnyEncodable(laneIndex),
            "startMs": AnyEncodable(startMs),
            "durationMs": AnyEncodable(durationMs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AudioGenerationAPIResponse.self, from: data)
    }

    public func previewStitch(
        token: String,
        projectId: String,
        transitionStyle: String = "crossfade",
        captionsEnabled: Bool = false
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/preview"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "transitionStyle": AnyEncodable(transitionStyle),
            "captionsEnabled": AnyEncodable(captionsEnabled)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func applyTransitions(
        token: String,
        projectId: String,
        transitionStyle: String = "crossfade"
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/transitions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "transitionStyle": AnyEncodable(transitionStyle)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func colorMatchStitch(
        token: String,
        projectId: String,
        colorMatchMode: String = "balanced"
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/color-match"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "colorMatchMode": AnyEncodable(colorMatchMode)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func bakeCaptions(
        token: String,
        projectId: String,
        captionsEnabled: Bool = true
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/captions/bake"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "captionsEnabled": AnyEncodable(captionsEnabled)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func normalizeLoudness(
        token: String,
        projectId: String,
        targetLufs: Int = -14
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/loudness/normalize"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "targetLufs": AnyEncodable(targetLufs)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func finalStitch(
        token: String,
        projectId: String,
        transitionStyle: String = "crossfade",
        captionsEnabled: Bool = false,
        resolution: String = "1080p"
    ) async throws -> StitchOperationResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/stitch/final"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "transitionStyle": AnyEncodable(transitionStyle),
            "captionsEnabled": AnyEncodable(captionsEnabled),
            "resolution": AnyEncodable(resolution)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StitchOperationResponse.self, from: data)
    }

    public func exportFinal(
        token: String,
        projectId: String,
        resolution: String = "1080p",
        captionsEnabled: Bool = false,
        includeArchive: Bool = true,
        publishTarget: String = "none"
    ) async throws -> Job {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/export/final"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "resolution": AnyEncodable(resolution),
            "captionsEnabled": AnyEncodable(captionsEnabled),
            "includeArchive": AnyEncodable(includeArchive),
            "publishTarget": AnyEncodable(publishTarget),
            "publishToPubfuse": AnyEncodable(publishTarget == "pubfuse")
        ] as [String: AnyEncodable])
        let (data, response) = try await performDataRequest(request, context: "exportFinal")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateJobResponse.self, from: data).job
    }

    public func listScenes(token: String, projectId: String) async throws -> [StoryScene] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/scenes"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListScenesResponse.self, from: data).scenes
    }

    public func generateStoryboard(
        token: String,
        projectId: String,
        logline: String,
        targetDurationMinutes: Int,
        tone: String
    ) async throws -> [StoryScene] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/storyboard/generate"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "logline": AnyEncodable(logline),
            "targetDurationMinutes": AnyEncodable(targetDurationMinutes),
            "tone": AnyEncodable(tone)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateStoryboardResponse.self, from: data).scenes
    }

    public func reviseScene(
        token: String,
        projectId: String,
        sceneId: String,
        title: String,
        revision: String,
        orderIndex: Int,
        mood: String
    ) async throws -> StoryScene {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/scenes/\(sceneId)"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "title": AnyEncodable(title),
            "revision": AnyEncodable(revision),
            "orderIndex": AnyEncodable(orderIndex),
            "mood": AnyEncodable(mood)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateSceneResponse.self, from: data).scene
    }

    public func quoteShot(token: String, projectId: String, prompt: String, modelTier: String) async throws -> ShotQuote {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots/quote"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["prompt": prompt, "modelTier": modelTier])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(QuoteShotResponse.self, from: data).quote
    }

    public func createShot(
        token: String,
        projectId: String,
        prompt: String,
        modelTier: String,
        characterLocks: [String] = []
    ) async throws -> Shot {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "prompt": AnyEncodable(prompt),
            "modelTier": AnyEncodable(modelTier),
            "characterLocks": AnyEncodable(characterLocks)
        ] as [String: AnyEncodable])
        let (data, response) = try await performDataRequest(request, context: "createShot")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateShotResponse.self, from: data).shot
    }

    public func listCharacters(token: String, projectId: String) async throws -> [CharacterProfile] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/characters"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListCharactersResponse.self, from: data).characters
    }

    public func createCharacter(token: String, projectId: String, name: String, description: String) async throws -> CharacterProfile {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/characters"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "name": AnyEncodable(name),
            "description": AnyEncodable(description)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateCharacterResponse.self, from: data).character
    }

    public func trainCharacter(token: String, projectId: String, characterId: String) async throws -> CharacterProfile {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/characters/\(characterId)/train"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateCharacterResponse.self, from: data).character
    }

    public func generateShot(token: String, projectId: String, shotId: String) async throws -> GenerateShotResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots/\(shotId)/generate"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await performDataRequest(request, context: "generateShot")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateShotResponse.self, from: data)
    }

    public func retryShot(token: String, projectId: String, shotId: String) async throws -> GenerateShotResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots/\(shotId)/retry"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateShotResponse.self, from: data)
    }

    public func deleteShot(token: String, projectId: String, shotId: String) async throws {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots/\(shotId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    public func listJobs(token: String, projectId: String) async throws -> [Job] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await performDataRequest(request, context: "listJobs")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListJobsResponse.self, from: data).jobs
    }

    public func createJob(token: String, projectId: String, kind: String = "clip") async throws -> Job {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["kind": kind])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateJobResponse.self, from: data).job
    }

    public func retryJob(token: String, projectId: String, jobId: String) async throws -> GenerateShotResponse {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs/\(jobId)/retry"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateShotResponse.self, from: data)
    }

    public func deleteJob(token: String, projectId: String, jobId: String) async throws {
        do {
            var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs/\(jobId)"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            return
        } catch {
            guard isMissingRouteError(error) else {
                throw error
            }
            // Compatibility fallback for older deployed gateways that don't expose DELETE /jobs/:id yet.
            let existingJobs = try await listJobs(token: token, projectId: projectId)
            let existingKind = existingJobs.first(where: { $0.id == jobId })?.kind ?? "clip"
            try await upsertDeletedJob(token: token, projectId: projectId, jobId: jobId, kind: existingKind)
        }
    }

    public func getBalance(token: String) async throws -> Int {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/sparks/balance"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(BalanceResponse.self, from: data).balance
    }

    public func streamProjectEvents(token: String, projectId: String) -> AsyncThrowingStream<ProjectEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/events"))
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    DiagnosticsLogger.apiRequestStart(method: "GET", url: request.url ?? baseURL, context: "streamProjectEvents")

                    let (bytes, response) = try await makeStreamSession().bytes(for: request)
                    try validateStatus(response: response)
                    if let http = response as? HTTPURLResponse {
                        DiagnosticsLogger.apiRequestSuccess(
                            method: "GET",
                            url: request.url ?? baseURL,
                            statusCode: http.statusCode,
                            context: "streamProjectEvents"
                        )
                    }

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        if line.hasPrefix("data: ") {
                            dataLines.append(String(line.dropFirst("data: ".count)))
                            continue
                        }
                        if line == "data:" {
                            dataLines.append("")
                            continue
                        }
                        if line.isEmpty {
                            if dataLines.isEmpty {
                                continue
                            }
                            let payload = dataLines.joined(separator: "\n")
                            dataLines.removeAll(keepingCapacity: true)
                            guard let data = payload.data(using: .utf8) else {
                                continue
                            }
                            if let event = try? JSONDecoder().decode(ProjectEvent.self, from: data) {
                                continuation.yield(event)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    if isExpectedEventStreamTimeout(error) {
                        DiagnosticsLogger.renderStatus(message: "event stream read timeout; reconnecting")
                        continuation.finish()
                        return
                    }
                    DiagnosticsLogger.apiRequestFailure(
                        method: "GET",
                        url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/events"),
                        context: "streamProjectEvents",
                        message: error.localizedDescription
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeStreamSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private func isExpectedEventStreamTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        return false
    }

    private func buildURL(path: String) -> URL {
        buildURL(baseURL: baseURL, path: path)
    }

    private func buildURL(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components.path = "/\(requestPath)"
        } else {
            components.path = "/\(basePath)/\(requestPath)"
        }

        return components.url ?? baseURL
    }

    private func performDataRequest(_ request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        let method = request.httpMethod ?? "GET"
        let url = request.url ?? baseURL
        DiagnosticsLogger.apiRequestStart(method: method, url: url, context: context)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                DiagnosticsLogger.apiRequestSuccess(method: method, url: url, statusCode: http.statusCode, context: context)
            }
            return (data, response)
        } catch {
            DiagnosticsLogger.apiRequestFailure(method: method, url: url, context: context, message: error.localizedDescription)
            throw error
        }
    }

    private func validateAuth(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let message = String(data: data, encoding: .utf8), !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NSError(domain: "PubfuseAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(
                domain: "PubfuseAuth",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)]
            )
        }
    }

    private func isMissingRouteError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "APIClient", nsError.code == 404 else {
            return false
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("endpoint not found") || message.contains("not found")
    }

    private func upsertDeletedJob(token: String, projectId: String, jobId: String, kind: String) async throws {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "id": AnyEncodable(jobId),
            "kind": AnyEncodable(kind),
            "status": AnyEncodable("deleted"),
            "inputPayload": AnyEncodable([String: String]()),
            "outputPayload": AnyEncodable([String: String]()),
            "costToUsCents": AnyEncodable(0)
        ] as [String: AnyEncodable])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message: String
            var userInfo: [String: Any] = [:]
            if let envelope {
                if envelope.code == "NOT_FOUND" {
                    message = "Endpoint not found. Restart the API gateway so it picks up the latest routes."
                } else {
                    message = envelope.error
                }
                userInfo[CinefuseAPIErrorUserInfoKey.errorCode] = envelope.code
                if let currentStatus = envelope.currentStatus {
                    userInfo[CinefuseAPIErrorUserInfoKey.currentStatus] = currentStatus
                }
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unexpected error"
            }
            userInfo[NSLocalizedDescriptionKey] = message
            throw NSError(domain: "CinefuseAPI", code: http.statusCode, userInfo: userInfo)
        }
    }

    private func validateStatus(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "CinefuseAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

private struct AudioMixExportRequestBody: Codable {
    let idempotencyKey: String
}

private struct ErrorEnvelope: Codable {
    let error: String
    let code: String
    let currentStatus: String?
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeImpl = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
