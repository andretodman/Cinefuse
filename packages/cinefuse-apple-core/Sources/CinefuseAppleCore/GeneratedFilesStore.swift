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

public actor GeneratedFilesStore {
    private struct Manifest: Codable {
        var remoteToLocalRelativePath: [String: String]
    }

    private let fileManager: FileManager
    private let session: URLSession

    public init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    public func rootDirectoryURL() throws -> URL {
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

    /// When set, used for the HTTP fetch only; manifest keys remain `remoteURLString` (canonical artifact URL from API).
    /// For same-host ``…/api/v1/cinefuse/projects/…/files/…`` URLs, pass ``bearerToken`` and ``authorizedApiBaseURLString`` so the download matches authenticated API access (otherwise the gateway returns 401).
    public func syncFile(
        projectId: String,
        remoteURLString: String,
        preferredBaseName: String,
        fetchURLString: String? = nil,
        bearerToken: String? = nil,
        authorizedApiBaseURLString: String? = nil
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

        let fetchURLResolved = fetchURLString.flatMap { URL(string: $0) } ?? remoteURL

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
            let (data, response): (Data, URLResponse)
            if let authToken = Self.bearerTokenForProjectFileFetch(
                url: fetchURLResolved,
                bearerToken: bearerToken,
                authorizedApiBaseURLString: authorizedApiBaseURLString
            ) {
                var request = URLRequest(url: fetchURLResolved)
                request.httpMethod = "GET"
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await session.data(for: request)
            } else {
                (data, response) = try await session.data(from: fetchURLResolved)
            }
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

    /// Returns the trimmed bearer token when the fetch URL is a Cinefuse project file on the same host as ``authorizedApiBaseURLString``.
    private nonisolated static func bearerTokenForProjectFileFetch(
        url: URL,
        bearerToken: String?,
        authorizedApiBaseURLString: String?
    ) -> String? {
        let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return nil }
        let baseStr = authorizedApiBaseURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseStr.isEmpty, let baseURL = URL(string: baseStr), let baseHost = baseURL.host, let urlHost = url.host else {
            return nil
        }
        guard baseHost.caseInsensitiveCompare(urlHost) == .orderedSame else { return nil }
        let path = url.path.lowercased()
        guard path.contains("/api/v1/cinefuse/projects/"), path.contains("/files/") else { return nil }
        return token
    }

    public func thumbnailURL(
        projectId: String,
        clipName: String,
        shotId: String,
        orderIndex: Int?
    ) throws -> URL {
        let directory = try ensureThumbnailFolder(projectId: projectId)
        let fileName = thumbnailFileName(
            clipName: clipName,
            shotId: shotId,
            orderIndex: orderIndex
        )
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    public func existingThumbnailURL(
        projectId: String,
        clipName: String,
        shotId: String,
        orderIndex: Int?
    ) throws -> URL? {
        let url = try thumbnailURL(
            projectId: projectId,
            clipName: clipName,
            shotId: shotId,
            orderIndex: orderIndex
        )
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    public func writeThumbnailData(
        _ data: Data,
        projectId: String,
        clipName: String,
        shotId: String,
        orderIndex: Int?
    ) throws -> URL {
        let url = try thumbnailURL(
            projectId: projectId,
            clipName: clipName,
            shotId: shotId,
            orderIndex: orderIndex
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    public func thumbnailFileName(clipName: String, shotId: String, orderIndex: Int?) -> String {
        let sanitizedClipName = sanitizeFileName(clipName)
        let sanitizedShotId = sanitizeFileName(shotId)
        let clipToken = sanitizedClipName == "generated-file" ? "shot" : sanitizedClipName
        let orderToken = orderIndex.map(String.init) ?? "0"
        return "\(clipToken)-\(orderToken)-\(sanitizedShotId).jpg"
    }

    private func ensureProjectFolder(projectId: String) throws -> URL {
        let root = try rootDirectoryURL()
        let folder = root.appendingPathComponent(sanitizeFileName(projectId), isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func ensureThumbnailFolder(projectId: String) throws -> URL {
        let projectFolder = try ensureProjectFolder(projectId: projectId)
        let thumbnailsFolder = projectFolder.appendingPathComponent("thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: thumbnailsFolder.path) {
            try fileManager.createDirectory(at: thumbnailsFolder, withIntermediateDirectories: true)
        }
        return thumbnailsFolder
    }

    private func inferredExtension(from remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ext.isEmpty {
            return sanitizeFileName(ext).lowercased()
        }
        let s = remoteURL.absoluteString.lowercased()
        if s.contains(".mp3") || s.contains("/mpeg") || s.contains("audio/mpeg") {
            return "mp3"
        }
        if s.contains(".wav") || s.contains("audio/wav") {
            return "wav"
        }
        if s.contains(".m4a") || s.contains(".aac") {
            return "m4a"
        }
        return "mp4"
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

extension GeneratedFilesStore {
    /// Dev stub URLs use hostname `files.cinefuse.test`, which does not resolve on-device. Map them to the API gateway ``/api/v1/cinefuse/stub-media`` route using the same origin as ``APIClient``.
    public static func fetchURLStringForRemoteArtifact(
        remoteURLString: String,
        apiGatewayBaseURLString: String?
    ) -> String {
        guard let remote = URL(string: remoteURLString),
              let host = remote.host?.lowercased(),
              host == "files.cinefuse.test",
              let baseStr = apiGatewayBaseURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseStr.isEmpty,
              let base = URL(string: baseStr)
        else {
            return remoteURLString
        }
        let suffix = "/stub-media" + remote.path
        guard let resolved = URL(string: APIClient.cinefusePrefix + suffix, relativeTo: base) else {
            return remoteURLString
        }
        return resolved.absoluteURL.absoluteString
    }
}
