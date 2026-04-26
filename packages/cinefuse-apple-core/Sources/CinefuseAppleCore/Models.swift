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
}

public struct ListShotsResponse: Codable {
    public let shots: [Shot]
}

public struct CreateShotResponse: Codable {
    public let shot: Shot
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
    public var userId: String = ""
    public var isAuthenticated = false
    public var projects: [Project] = []
    public var balance: Int = 0
    public var isLoading = false
    public var errorMessage: String?

    public var bearerToken: String {
        "user:\(userId)"
    }

    public init() {}
}
