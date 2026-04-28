import Foundation

public enum LocalFileSyncStatus: String, Codable {
    case pending
    case synced
    case alreadyPresent
    case downloadFailed
    case writeFailed
}

public struct LocalFileRecord: Codable, Identifiable {
    public let id: String
    public let remoteURL: String
    public let localPath: String?
    public let status: LocalFileSyncStatus
    public let errorMessage: String?
    public let updatedAt: Date

    public init(
        id: String,
        remoteURL: String,
        localPath: String?,
        status: LocalFileSyncStatus,
        errorMessage: String?,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.localPath = localPath
        self.status = status
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

actor GeneratedFilesStore {
    private struct Manifest: Codable {
        var remoteToLocalRelativePath: [String: String]
    }

    private let fileManager: FileManager
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func rootDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "GeneratedFilesStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Documents directory unavailable."
            ])
        }
        let root = documentsURL.appendingPathComponent("Cinefuse Generated", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    func syncFile(
        projectId: String,
        remoteURLString: String,
        preferredBaseName: String
    ) async -> LocalFileRecord {
        guard let remoteURL = URL(string: remoteURLString) else {
            return LocalFileRecord(
                id: remoteURLString,
                remoteURL: remoteURLString,
                localPath: nil,
                status: .downloadFailed,
                errorMessage: "Invalid remote URL."
            )
        }

        do {
            let projectFolder = try ensureProjectFolder(projectId: projectId)
            let manifestURL = projectFolder.appendingPathComponent(".manifest.json", isDirectory: false)
            var manifest = try loadManifest(at: manifestURL)
            let cleanBaseName = sanitizeFileName(preferredBaseName)
            let fileExtension = inferredExtension(from: remoteURL)

            if let existingRelativePath = manifest.remoteToLocalRelativePath[remoteURLString] {
                let existingURL = projectFolder.appendingPathComponent(existingRelativePath, isDirectory: false)
                if fileManager.fileExists(atPath: existingURL.path) {
                    DiagnosticsLogger.fileSyncSuccess(remoteURL: remoteURLString, localPath: existingURL.path, reused: true)
                    return LocalFileRecord(
                        id: remoteURLString,
                        remoteURL: remoteURLString,
                        localPath: existingURL.path,
                        status: .alreadyPresent,
                        errorMessage: nil
                    )
                }
            }

            let destinationURL = uniqueDestinationURL(
                in: projectFolder,
                baseName: cleanBaseName,
                fileExtension: fileExtension
            )

            DiagnosticsLogger.fileSyncStart(remoteURL: remoteURLString, destination: destinationURL.path)
            let (data, response) = try await session.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let message = "HTTP \(http.statusCode)"
                DiagnosticsLogger.fileSyncFailure(remoteURL: remoteURLString, destination: destinationURL.path, message: message)
                return LocalFileRecord(
                    id: remoteURLString,
                    remoteURL: remoteURLString,
                    localPath: nil,
                    status: .downloadFailed,
                    errorMessage: message
                )
            }

            do {
                try data.write(to: destinationURL, options: .atomic)
            } catch {
                DiagnosticsLogger.fileSyncFailure(remoteURL: remoteURLString, destination: destinationURL.path, message: error.localizedDescription)
                return LocalFileRecord(
                    id: remoteURLString,
                    remoteURL: remoteURLString,
                    localPath: nil,
                    status: .writeFailed,
                    errorMessage: error.localizedDescription
                )
            }

            manifest.remoteToLocalRelativePath[remoteURLString] = destinationURL.lastPathComponent
            try saveManifest(manifest, to: manifestURL)
            DiagnosticsLogger.fileSyncSuccess(remoteURL: remoteURLString, localPath: destinationURL.path, reused: false)
            return LocalFileRecord(
                id: remoteURLString,
                remoteURL: remoteURLString,
                localPath: destinationURL.path,
                status: .synced,
                errorMessage: nil
            )
        } catch {
            DiagnosticsLogger.fileSyncFailure(remoteURL: remoteURLString, destination: "unknown", message: error.localizedDescription)
            return LocalFileRecord(
                id: remoteURLString,
                remoteURL: remoteURLString,
                localPath: nil,
                status: .writeFailed,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func ensureProjectFolder(projectId: String) throws -> URL {
        let root = try rootDirectoryURL()
        let folder = root.appendingPathComponent(sanitizeFileName(projectId), isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func inferredExtension(from remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if ext.isEmpty {
            return "mp4"
        }
        return sanitizeFileName(ext).lowercased()
    }

    private func uniqueDestinationURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)", isDirectory: false)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)", isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    private func sanitizeFileName(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "generated-file" : collapsed
    }

    private func loadManifest(at url: URL) throws -> Manifest {
        guard fileManager.fileExists(atPath: url.path) else {
            return Manifest(remoteToLocalRelativePath: [:])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func saveManifest(_ manifest: Manifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}
