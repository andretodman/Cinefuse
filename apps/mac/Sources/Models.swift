import Foundation
import Observation

struct Project: Codable, Identifiable {
    let id: String
    let ownerUserId: String
    let title: String
    let logline: String
    let targetDurationMinutes: Int
    let tone: String
    let currentPhase: String
}

struct ListProjectsResponse: Codable {
    let projects: [Project]
}

struct CreateProjectResponse: Codable {
    let project: Project
}

struct Shot: Codable, Identifiable {
    let id: String
    let projectId: String
    let prompt: String
    let modelTier: String
    let status: String
    let clipUrl: String?
}

struct ListShotsResponse: Codable {
    let shots: [Shot]
}

struct CreateShotResponse: Codable {
    let shot: Shot
}

struct Job: Codable, Identifiable {
    let id: String
    let projectId: String
    let shotId: String?
    let kind: String
    let status: String
    let costToUsCents: Int
}

struct ListJobsResponse: Codable {
    let jobs: [Job]
}

struct CreateJobResponse: Codable {
    let job: Job
}

struct BalanceResponse: Codable {
    let userId: String
    let balance: Int
}

@Observable
final class AppModel {
    var userId: String = ""
    var isAuthenticated = false
    var projects: [Project] = []
    var balance: Int = 0
    var isLoading = false
    var errorMessage: String?

    var bearerToken: String {
        "user:\(userId)"
    }
}
