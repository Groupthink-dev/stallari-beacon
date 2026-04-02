import Foundation

// MARK: - Errors

/// Errors thrown by ``ReportStore`` operations.
public enum ReportStoreError: Error, Sendable {
    case directoryCreationFailed(path: String, underlying: Error)
    case writeFailed(reportId: String, underlying: Error)
    case readFailed(path: String, underlying: Error)
    case reportNotFound(reportId: String)
    case deleteFailed(reportId: String, underlying: Error)
}

// MARK: - ReportStore

/// Persists ``BeaconReport`` instances as human-readable JSON files on disk.
///
/// Reports flow through two directories:
/// - `pending/` — awaiting user consent and transmission
/// - `sent/` — successfully transmitted, pruned after 30 days
///
/// Each report is stored as `{report_id}.json` with pretty-printed, sorted-key
/// JSON so that users can inspect reports in any text editor.
public actor ReportStore {

    // MARK: - Properties

    private let baseDirectory: URL
    private let fileManager: FileManager

    private var pendingDirectory: URL { baseDirectory.appendingPathComponent("pending") }
    private var sentDirectory: URL { baseDirectory.appendingPathComponent("sent") }

    private var directoriesCreated = false

    // MARK: - Codecs

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Init

    /// Creates a report store.
    ///
    /// - Parameter baseDirectory: Override for testing. Defaults to
    ///   `~/.config/sidereal/beacon/`.
    public init(baseDirectory: URL? = nil) {
        self.fileManager = .default
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".config/sidereal/beacon")
        }
    }

    // MARK: - Public API

    /// Writes a report to the `pending/` directory.
    public func save(_ report: BeaconReport) async throws {
        try ensureDirectories()
        let data = try encodeReport(report)
        let url = pendingDirectory.appendingPathComponent("\(report.reportId).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ReportStoreError.writeFailed(reportId: report.reportId, underlying: error)
        }
    }

    /// Returns all pending reports, sorted by timestamp descending (newest first).
    public func listPending() async throws -> [BeaconReport] {
        try loadReports(from: pendingDirectory)
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Returns all sent reports.
    public func listSent() async throws -> [BeaconReport] {
        try loadReports(from: sentDirectory)
    }

    /// Finds a report by ID in either `pending/` or `sent/`.
    ///
    /// Returns `nil` if no report with the given ID exists.
    public func get(_ reportId: String) async throws -> BeaconReport? {
        if let report = try loadReport(id: reportId, from: pendingDirectory) {
            return report
        }
        return try loadReport(id: reportId, from: sentDirectory)
    }

    /// Deletes a report by ID from either `pending/` or `sent/`.
    public func delete(_ reportId: String) async throws {
        let filename = "\(reportId).json"
        let pendingURL = pendingDirectory.appendingPathComponent(filename)
        let sentURL = sentDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: pendingURL.path) {
            do {
                try fileManager.removeItem(at: pendingURL)
                return
            } catch {
                throw ReportStoreError.deleteFailed(reportId: reportId, underlying: error)
            }
        }

        if fileManager.fileExists(atPath: sentURL.path) {
            do {
                try fileManager.removeItem(at: sentURL)
                return
            } catch {
                throw ReportStoreError.deleteFailed(reportId: reportId, underlying: error)
            }
        }

        throw ReportStoreError.reportNotFound(reportId: reportId)
    }

    /// Moves a report from `pending/` to `sent/`.
    public func markSent(_ reportId: String) async throws {
        try ensureDirectories()
        let filename = "\(reportId).json"
        let source = pendingDirectory.appendingPathComponent(filename)
        let destination = sentDirectory.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: source.path) else {
            throw ReportStoreError.reportNotFound(reportId: reportId)
        }

        do {
            // Remove any existing file at the destination (re-send scenario).
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw ReportStoreError.writeFailed(reportId: reportId, underlying: error)
        }
    }

    /// Deletes sent reports older than the given number of days.
    ///
    /// - Returns: The number of reports deleted.
    @discardableResult
    public func pruneSent(olderThan days: Int = 30) async throws -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let reports = try loadReports(from: sentDirectory)
        var deleted = 0

        for report in reports where report.timestamp < cutoff {
            let url = sentDirectory.appendingPathComponent("\(report.reportId).json")
            do {
                try fileManager.removeItem(at: url)
                deleted += 1
            } catch {
                throw ReportStoreError.deleteFailed(reportId: report.reportId, underlying: error)
            }
        }

        return deleted
    }

    /// Removes all reports from both `pending/` and `sent/`.
    ///
    /// Intended for the "Delete all data" user action.
    public func deleteAll() async throws {
        try removeContents(of: pendingDirectory)
        try removeContents(of: sentDirectory)
    }

    /// Returns the number of reports awaiting consent/send.
    public func pendingCount() async throws -> Int {
        guard fileManager.fileExists(atPath: pendingDirectory.path) else { return 0 }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: pendingDirectory,
                includingPropertiesForKeys: nil
            )
            return contents.filter { $0.pathExtension == "json" }.count
        } catch {
            throw ReportStoreError.readFailed(path: pendingDirectory.path, underlying: error)
        }
    }

    // MARK: - Private Helpers

    /// Creates `pending/` and `sent/` directories if they don't already exist.
    private func ensureDirectories() throws {
        guard !directoriesCreated else { return }
        for directory in [pendingDirectory, sentDirectory] {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ReportStoreError.directoryCreationFailed(
                    path: directory.path,
                    underlying: error
                )
            }
        }
        directoriesCreated = true
    }

    /// Encodes a report to pretty-printed JSON data.
    private func encodeReport(_ report: BeaconReport) throws -> Data {
        do {
            return try encoder.encode(report)
        } catch {
            throw ReportStoreError.writeFailed(reportId: report.reportId, underlying: error)
        }
    }

    /// Loads a single report by ID from a directory, returning `nil` if the file
    /// doesn't exist.
    private func loadReport(id: String, from directory: URL) throws -> BeaconReport? {
        let url = directory.appendingPathComponent("\(id).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(BeaconReport.self, from: data)
        } catch {
            throw ReportStoreError.readFailed(path: url.path, underlying: error)
        }
    }

    /// Loads and decodes all `.json` reports in a directory.
    ///
    /// Returns an empty array if the directory doesn't exist yet.
    private func loadReports(from directory: URL) throws -> [BeaconReport] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw ReportStoreError.readFailed(path: directory.path, underlying: error)
        }

        return try urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(BeaconReport.self, from: data)
                } catch {
                    throw ReportStoreError.readFailed(path: url.path, underlying: error)
                }
            }
    }

    /// Removes all files within a directory. Does nothing if the directory
    /// doesn't exist.
    private func removeContents(of directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw ReportStoreError.readFailed(path: directory.path, underlying: error)
        }

        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw ReportStoreError.deleteFailed(
                    reportId: url.deletingPathExtension().lastPathComponent,
                    underlying: error
                )
            }
        }
    }
}
