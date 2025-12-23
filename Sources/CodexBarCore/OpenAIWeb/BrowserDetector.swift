import Foundation

#if os(macOS)
import ApplicationServices
#endif

/// Detects and prioritizes web browsers for cookie extraction.
///
/// This utility identifies which browser is most likely to have valid session cookies by:
/// 1. Detecting the system's default browser
/// 2. Checking which browsers have cookies for target domains
/// 3. Prioritizing by recency and default status
enum BrowserDetector {
    enum Browser: String, CaseIterable, Sendable {
        case safari = "Safari"
        case chrome = "Chrome"
        case brave = "Brave"
        case edge = "Microsoft Edge"
        case vivaldi = "Vivaldi"
        case arc = "Arc"
        case firefox = "Firefox"
        case firefoxDeveloperEdition = "Firefox Developer Edition"

        var bundleIdentifier: String {
            switch self {
            case .safari: return "com.apple.Safari"
            case .chrome: return "com.google.Chrome"
            case .brave: return "com.brave.Browser"
            case .edge: return "com.microsoft.edgemac"
            case .vivaldi: return "com.vivaldi.Vivaldi"
            case .arc: return "company.thebrowser.Browser"
            case .firefox: return "org.mozilla.firefox"
            case .firefoxDeveloperEdition: return "org.mozilla.firefoxdeveloperedition"
            }
        }

        var supportsCookieExtraction: Bool {
            // Support Safari, Chromium-based browsers, and Firefox
            switch self {
            case .safari, .chrome, .brave, .edge, .vivaldi, .firefox, .firefoxDeveloperEdition:
                return true
            case .arc:
                return false
            }
        }
    }

    struct BrowserPriority: Sendable, Comparable {
        let browser: Browser
        let isDefault: Bool
        let hasCookies: Bool
        let cookieAge: TimeInterval?

        static func < (lhs: BrowserPriority, rhs: BrowserPriority) -> Bool {
            // Default browser with cookies wins
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && lhs.hasCookies
            }
            // Both default or both non-default: prefer one with cookies
            if lhs.hasCookies != rhs.hasCookies {
                return lhs.hasCookies
            }
            // Both have cookies: prefer more recent
            if let lAge = lhs.cookieAge, let rAge = rhs.cookieAge {
                return lAge < rAge // smaller age = more recent
            }
            // Fallback: prefer Safari (no Keychain prompt)
            if lhs.browser == .safari { return true }
            if rhs.browser == .safari { return false }
            return false
        }
    }

    /// Returns browsers in priority order for cookie extraction.
    /// - Parameter domains: Domain patterns to check for cookies (e.g., ["chatgpt.com", "openai.com"])
    /// - Returns: Array of browsers sorted by likelihood of having valid cookies
    static func prioritizeBrowsers(forDomains domains: [String]) -> [Browser] {
        let defaultBrowser = self.detectDefaultBrowser()
        var priorities: [BrowserPriority] = []

        for browser in Browser.allCases where browser.supportsCookieExtraction {
            let hasCookies: Bool
            let cookieAge: TimeInterval?

            switch browser {
            case .safari:
                (hasCookies, cookieAge) = self.checkSafariCookies(domains: domains)
            case .chrome, .brave, .edge, .vivaldi:
                (hasCookies, cookieAge) = self.checkChromiumCookies(browser: browser, domains: domains)
            case .firefox, .firefoxDeveloperEdition:
                (hasCookies, cookieAge) = self.checkFirefoxCookies(browser: browser, domains: domains)
            case .arc:
                (hasCookies, cookieAge) = (false, nil)
            }

            priorities.append(BrowserPriority(
                browser: browser,
                isDefault: browser == defaultBrowser,
                hasCookies: hasCookies,
                cookieAge: cookieAge))
        }

        return priorities.sorted().reversed().map(\.browser)
    }

    /// Detects the system's default web browser.
    static func detectDefaultBrowser() -> Browser? {
        #if os(macOS)
        // Try to get the default handler for http URLs
        guard let bundleID = LSCopyDefaultHandlerForURLScheme("http" as CFString)?.takeRetainedValue() as String?
        else {
            return nil
        }

        return Browser.allCases.first { $0.bundleIdentifier == bundleID }
        #else
        return nil
        #endif
    }

    /// Checks if Safari has cookies for the given domains and returns recency.
    private static func checkSafariCookies(domains: [String]) -> (hasCookies: Bool, age: TimeInterval?) {
        let candidates = self.safariCookiePaths()
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date
            else {
                continue
            }
            let age = Date().timeIntervalSince(modDate)
            // Check if file is not too old (within last 90 days)
            if age < 90 * 24 * 3600 {
                return (true, age)
            }
        }
        return (false, nil)
    }

    /// Checks if a Chromium-based browser has cookies for the given domains and returns recency.
    private static func checkChromiumCookies(browser: Browser, domains: [String]) -> (hasCookies: Bool, age: TimeInterval?) {
        let paths = self.chromiumCookiePaths(browser: browser)
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date
            else {
                continue
            }
            let age = Date().timeIntervalSince(modDate)
            // Check if file is not too old (within last 90 days)
            if age < 90 * 24 * 3600 {
                return (true, age)
            }
        }
        return (false, nil)
    }

    private static func safariCookiePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Cookies/Cookies.binarycookies",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        ]
    }

    private static func chromiumCookiePaths(browser: Browser) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupportBase = "\(home)/Library/Application Support"

        let browserDir: String
        switch browser {
        case .chrome:
            browserDir = "Google/Chrome"
        case .brave:
            browserDir = "BraveSoftware/Brave-Browser"
        case .edge:
            browserDir = "Microsoft Edge"
        case .vivaldi:
            browserDir = "Vivaldi"
        default:
            return []
        }

        let profileNames = ["Default", "Profile 1", "Profile 2", "Profile 3"]
        return profileNames.map { profile in
            "\(appSupportBase)/\(browserDir)/\(profile)/Cookies"
        }
    }

    /// Checks if Firefox has cookies for the given domains and returns recency.
    private static func checkFirefoxCookies(browser: Browser, domains: [String]) -> (hasCookies: Bool, age: TimeInterval?) {
        let paths = self.firefoxCookiePaths(browser: browser)
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date
            else {
                continue
            }
            let age = Date().timeIntervalSince(modDate)
            // Check if file is not too old (within last 90 days)
            if age < 90 * 24 * 3600 {
                return (true, age)
            }
        }
        return (false, nil)
    }

    private static func firefoxCookiePaths(browser: Browser) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let firefoxBase: String
        
        switch browser {
        case .firefox:
            firefoxBase = "\(home)/Library/Application Support/Firefox"
        case .firefoxDeveloperEdition:
            firefoxBase = "\(home)/Library/Application Support/Firefox Developer Edition"
        default:
            return []
        }
        
        // Firefox uses profile directories with random names like "abc123.default" or "xyz789.dev-edition-default"
        // We need to search for profiles and find their cookies.sqlite files
        guard let profilesDir = URL(string: "file://\(firefoxBase)/Profiles"),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: profilesDir,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles])
        else {
            return []
        }
        
        return entries.compactMap { profileURL -> String? in
            guard let isDir = (try? profileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory),
                  isDir else {
                return nil
            }
            let cookiesFile = profileURL.appendingPathComponent("cookies.sqlite").path
            guard FileManager.default.fileExists(atPath: cookiesFile) else {
                return nil
            }
            return cookiesFile
        }
    }
}
