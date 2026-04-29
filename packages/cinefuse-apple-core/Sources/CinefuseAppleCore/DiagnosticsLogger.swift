import Foundation
import OSLog

enum DiagnosticsLogger {
    private static let subsystem = "com.cinefuse.applecore"
    private static let apiLogger = Logger(subsystem: subsystem, category: "api")
    private static let renderLogger = Logger(subsystem: subsystem, category: "render")
    private static let fileSyncLogger = Logger(subsystem: subsystem, category: "filesync")
    private static let eventLogger = Logger(subsystem: subsystem, category: "events")

    static func apiRequestStart(method: String, url: URL, context: String) {
        apiLogger.info("request start [\(context, privacy: .public)] \(method, privacy: .public) \(url.absoluteString, privacy: .public)")
    }

    static func apiRequestSuccess(method: String, url: URL, statusCode: Int, context: String) {
        apiLogger.info("request success [\(context, privacy: .public)] \(method, privacy: .public) \(url.absoluteString, privacy: .public) status=\(statusCode)")
    }

    static func apiRequestFailure(method: String, url: URL, context: String, message: String) {
        apiLogger.error("request failed [\(context, privacy: .public)] \(method, privacy: .public) \(url.absoluteString, privacy: .public) reason=\(message, privacy: .public)")
    }

    static func projectEventReceived(type: String, projectId: String, shotId: String?, jobId: String?) {
        eventLogger.info("event \(type, privacy: .public) project=\(projectId, privacy: .public) shot=\(shotId ?? "-", privacy: .public) job=\(jobId ?? "-", privacy: .public)")
    }

    static func renderStatus(message: String) {
        renderLogger.info("\(message, privacy: .public)")
    }

    /// Full diagnostics body when the user opens the status sheet (truncated for log size).
    static func renderPipelineSheet(summary: String, details: String) {
        let cap = 1600
        let clipped = details.count > cap ? String(details.prefix(cap)) + "…" : details
        renderLogger.info("[render_pipeline] sheet_open summary=\(summary, privacy: .public) details=\(clipped, privacy: .public)")
    }

    static func fileSyncStart(remoteURL: String, destination: String) {
        fileSyncLogger.info("sync start remote=\(remoteURL, privacy: .public) destination=\(destination, privacy: .public)")
    }

    static func fileSyncSuccess(remoteURL: String, localPath: String, reused: Bool) {
        fileSyncLogger.info("sync success remote=\(remoteURL, privacy: .public) local=\(localPath, privacy: .public) reused=\(reused)")
    }

    static func fileSyncFailure(remoteURL: String, destination: String, message: String) {
        fileSyncLogger.error("sync failed remote=\(remoteURL, privacy: .public) destination=\(destination, privacy: .public) reason=\(message, privacy: .public)")
    }
}
