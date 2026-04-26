import Foundation

struct APIClient {
    let baseURL: URL
    static let cinefusePrefix = "/api/v1/cinefuse"

    init(baseURLString: String = ProcessInfo.processInfo.environment["CINEFUSE_API_BASE_URL"] ?? "http://localhost:4000") {
        self.baseURL = URL(string: baseURLString)!
    }

    func listProjects(token: String) async throws -> [Project] {
        var request = URLRequest(url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListProjectsResponse.self, from: data).projects
    }

    func createProject(token: String, title: String) async throws -> Project {
        var request = URLRequest(url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateProjectResponse.self, from: data).project
    }

    func listShots(token: String, projectId: String) async throws -> [Shot] {
        var request = URLRequest(
            url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots")
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListShotsResponse.self, from: data).shots
    }

    func createShot(token: String, projectId: String, prompt: String) async throws -> Shot {
        var request = URLRequest(
            url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects/\(projectId)/shots")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["prompt": prompt])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateShotResponse.self, from: data).shot
    }

    func listJobs(token: String, projectId: String) async throws -> [Job] {
        var request = URLRequest(
            url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs")
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ListJobsResponse.self, from: data).jobs
    }

    func createJob(token: String, projectId: String, kind: String = "clip") async throws -> Job {
        var request = URLRequest(
            url: baseURL.appending(path: "\(Self.cinefusePrefix)/projects/\(projectId)/jobs")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["kind": kind])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CreateJobResponse.self, from: data).job
    }

    func getBalance(token: String) async throws -> Int {
        var request = URLRequest(url: baseURL.appending(path: "\(Self.cinefusePrefix)/sparks/balance"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(BalanceResponse.self, from: data).balance
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unexpected error"
            throw NSError(domain: "CinefuseAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
