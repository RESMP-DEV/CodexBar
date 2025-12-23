import Foundation
import SQLite3

/// Reads cookies from Firefox and Firefox Developer Edition cookie databases.
///
/// Firefox stores cookies in an SQLite database (cookies.sqlite) in each profile directory.
/// Unlike Chrome, Firefox cookies are typically not encrypted, making extraction simpler.
enum FirefoxCookieImporter {
    enum ImportError: LocalizedError {
        case cookieDBNotFound(path: String)
        case sqliteFailed(message: String)

        var errorDescription: String? {
            switch self {
            case let .cookieDBNotFound(path): "Firefox Cookies DB not found at \(path)."
            case let .sqliteFailed(message): "Failed to read Firefox cookies: \(message)"
            }
        }
    }

    struct CookieRecord: Sendable {
        let host: String
        let name: String
        let path: String
        let value: String
        let expiry: Int64
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    struct CookieSource: Sendable {
        let label: String
        let records: [CookieRecord]
    }

    /// Loads cookies from all Firefox profiles (both regular Firefox and Firefox Developer Edition).
    /// - Parameter matchingDomains: Array of domain patterns to match (e.g., ["chatgpt.com", "openai.com"])
    /// - Returns: Array of cookie sources with matching records
    static func loadCookiesFromAllProfiles(matchingDomains domains: [String]) throws -> [CookieSource] {
        let firefoxVariants: [(name: String, profilesPath: String)] = [
            ("Firefox", "Firefox/Profiles"),
            ("Firefox Developer Edition", "Firefox Developer Edition/Profiles"),
        ]

        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library").appendingPathComponent("Application Support")

        var allCandidates: [FirefoxProfileCandidate] = []

        for (browserName, profilePath) in firefoxVariants {
            let profilesDir = appSupport.appendingPathComponent(profilePath)
            let candidates = Self.findFirefoxProfiles(profilesDir: profilesDir, browserName: browserName)
            allCandidates.append(contentsOf: candidates)
        }

        if allCandidates.isEmpty {
            let searchPaths = firefoxVariants.map { $0.profilesPath }.joined(separator: ", ")
            throw ImportError.cookieDBNotFound(path: "~/Library/Application Support/{\(searchPaths)}")
        }

        return try allCandidates.compactMap { candidate in
            guard FileManager.default.fileExists(atPath: candidate.cookiesDB.path) else { return nil }
            let records = try Self.readCookiesFromFirefoxDB(
                sourceDB: candidate.cookiesDB,
                matchingDomains: domains)
            guard !records.isEmpty else { return nil }
            return CookieSource(label: candidate.label, records: records)
        }
    }

    // MARK: - Profile discovery

    private struct FirefoxProfileCandidate: Sendable {
        let label: String
        let cookiesDB: URL
    }

    private static func findFirefoxProfiles(profilesDir: URL, browserName: String) -> [FirefoxProfileCandidate] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        return entries.compactMap { profileURL -> FirefoxProfileCandidate? in
            guard let isDir = (try? profileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory),
                  isDir else {
                return nil
            }

            let profileName = profileURL.lastPathComponent
            let cookiesDB = profileURL.appendingPathComponent("cookies.sqlite")

            guard FileManager.default.fileExists(atPath: cookiesDB.path) else {
                return nil
            }

            return FirefoxProfileCandidate(
                label: "\(browserName) (\(profileName))",
                cookiesDB: cookiesDB)
        }
    }

    // MARK: - SQLite read

    private static func readCookiesFromFirefoxDB(
        sourceDB: URL,
        matchingDomains: [String]) throws -> [CookieRecord]
    {
        // Firefox may have the DB locked; copy it to temp first
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-firefox-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let copiedDB = tempDir.appendingPathComponent("cookies.sqlite")
        try FileManager.default.copyItem(at: sourceDB, to: copiedDB)

        // Also copy WAL and SHM files if present
        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceDB.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) {
                let dst = URL(fileURLWithPath: copiedDB.path + suffix)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try Self.readCookies(fromDB: copiedDB.path, matchingDomains: matchingDomains)
    }

    private static func readCookies(
        fromDB path: String,
        matchingDomains: [String]) throws -> [CookieRecord]
    {
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        // Build WHERE clause with placeholders for parameterized query
        let placeholders = matchingDomains.enumerated().map { "host LIKE ?" }.joined(separator: " OR ")
        let sql = """
        SELECT host, name, path, value, expiry, isSecure, isHttpOnly
        FROM moz_cookies
        WHERE \(placeholders)
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        // Bind parameters for each domain (SQLite uses 1-based indexing)
        for (index, domain) in matchingDomains.enumerated() {
            let pattern = "%\(domain)%"
            if sqlite3_bind_text(stmt, Int32(index + 1), pattern, -1, nil) != SQLITE_OK {
                throw ImportError.sqliteFailed(message: "Failed to bind parameter")
            }
        }

        var out: [CookieRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let host = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let path = String(cString: sqlite3_column_text(stmt, 2))
            let value = String(cString: sqlite3_column_text(stmt, 3))
            let expiry = sqlite3_column_int64(stmt, 4)
            let isSecure = sqlite3_column_int(stmt, 5) != 0
            let isHTTPOnly = sqlite3_column_int(stmt, 6) != 0

            out.append(CookieRecord(
                host: host,
                name: name,
                path: path,
                value: value,
                expiry: expiry,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly))
        }
        return out
    }

    // MARK: - Conversion

    static func makeHTTPCookies(_ records: [CookieRecord]) -> [HTTPCookie] {
        records.compactMap { record in
            let domain = Self.normalizeDomain(record.host)
            guard !domain.isEmpty else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
                .secure: record.isSecure,
            ]
            props[.originURL] = Self.originURL(forDomain: domain)
            if record.isHTTPOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if record.expiry > 0 {
                // Firefox stores expiry as Unix timestamp (seconds since 1970)
                props[.expires] = Date(timeIntervalSince1970: TimeInterval(record.expiry))
            }
            return HTTPCookie(properties: props)
        }
    }

    private static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private static func originURL(forDomain domain: String) -> URL {
        let d = domain.lowercased()
        if d.contains("openai.com") {
            return URL(string: "https://openai.com")!
        }
        if d.contains("chatgpt.com") {
            return URL(string: "https://chatgpt.com")!
        }
        if d.contains("claude.ai") {
            return URL(string: "https://claude.ai")!
        }
        return URL(string: "https://\(domain)")!
    }
}
