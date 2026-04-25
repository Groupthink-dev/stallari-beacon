import Foundation

// MARK: - InstallID

/// Manages a stable per-install identifier that survives harness upgrades and pack
/// changes but is reset on full reinstall or user-initiated wipe.
///
/// The identifier has the format `ins_` followed by 16 hex characters (8 random bytes).
/// It is generated once on first access and persisted alongside ``BeaconConfig``.
///
/// Unlike `deviceId` (which stays local), `install_id` is transmitted in every report
/// and is visible to the platform operator in Astrolabe as the row identity in the
/// Fleet view.
public struct InstallID: Sendable {

    /// Prefix for all install identifiers.
    public static let prefix = "ins_"

    /// Expected total length: prefix (4) + 16 hex chars = 20.
    public static let expectedLength = 20

    private static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/stallari/beacon", isDirectory: true)
    }

    private static var installIdURL: URL {
        configDirectory.appendingPathComponent("install_id")
    }

    /// Load the persisted install ID, or generate and persist a new one.
    public static func loadOrCreate() -> String {
        let url = installIdURL

        // Try to read existing.
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           isValid(existing) {
            return existing
        }

        // Generate new.
        let id = generate()

        // Persist (best-effort — if this fails, we'll regenerate next time,
        // which is acceptable for a fresh install scenario).
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try id.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Silently continue — the ID is still valid for this session.
        }

        return id
    }

    /// Generate a fresh install ID: `ins_` + 16 random hex characters.
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(prefix)\(hex)"
    }

    /// Validate that a string is a well-formed install ID.
    public static func isValid(_ id: String) -> Bool {
        guard id.hasPrefix(prefix), id.count == expectedLength else { return false }
        let hex = id.dropFirst(prefix.count)
        return hex.allSatisfy { $0.isHexDigit }
    }

    /// Delete the persisted install ID. Used for user-initiated data wipe.
    public static func reset() {
        try? FileManager.default.removeItem(at: installIdURL)
    }
}
