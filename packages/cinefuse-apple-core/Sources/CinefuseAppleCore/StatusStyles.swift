import SwiftUI

enum StatusStyle {
    case queued
    case running
    case ready
    case failed
    case draft
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "queued":
            self = .queued
        case "running", "generating":
            self = .running
        case "ready", "done":
            self = .ready
        case "failed":
            self = .failed
        case "draft":
            self = .draft
        default:
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Processing"
        case .ready: "Ready"
        case .failed: "Failed"
        case .draft: "Draft"
        case .unknown: "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .queued: CinefuseTokens.ColorRole.warning
        case .running: CinefuseTokens.ColorRole.accent
        case .ready: CinefuseTokens.ColorRole.success
        case .failed: CinefuseTokens.ColorRole.danger
        case .draft: CinefuseTokens.ColorRole.textSecondary
        case .unknown: CinefuseTokens.ColorRole.textSecondary
        }
    }
}
