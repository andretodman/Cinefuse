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

    public func createShot(token: String, projectId: String, prompt: String, modelTier: String) async throws -> Shot {
        var request = URLRequest(url: buildURL(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["prompt": prompt, "modelTier": modelTier])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateShotResponse.self, from: data).shot
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
