import Foundation

public struct APIClient {
    public let baseURL: URL
    public static let cinefusePrefix = "/api/v1/cinefuse"

    public init(baseURLString: String = ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000") {
        self.baseURL = URL(string: baseURLString)!
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
    ) async throws -> AudioTrack {
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
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
    }

    public func generateScore(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioTrack {
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
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
    }

    public func generateSFX(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioTrack {
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
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
    }

    public func mixAudio(
        token: String,
        projectId: String,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioTrack {
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
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
    }

    public func lipsyncAudio(
        token: String,
        projectId: String,
        shotId: String?,
        title: String,
        laneIndex: Int,
        startMs: Int,
        durationMs: Int
    ) async throws -> AudioTrack {
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
        return try JSONDecoder().decode(CreateAudioTrackResponse.self, from: data).audioTrack
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GenerateShotResponse.self, from: data)
    }

    public func listJobs(token: String, projectId: String) async throws -> [Job] {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
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

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try validateStatus(response: response)

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
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func buildURL(path: String) -> URL {
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

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message: String
            if let envelope {
                if envelope.code == "NOT_FOUND" {
                    message = "Endpoint not found. Restart the API gateway so it picks up the latest routes."
                } else {
                    message = envelope.error
                }
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unexpected error"
            }
            throw NSError(domain: "CinefuseAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
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

private struct ErrorEnvelope: Codable {
    let error: String
    let code: String
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
