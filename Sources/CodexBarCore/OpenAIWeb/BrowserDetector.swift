import Foundation
import UniformTypeIdentifiers

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

        var bundleIdentifier: String {
            switch self {
            case .safari: return "com.apple.Safari"
            case .chrome: return "com.google.Chrome"
            case .brave: return "com.brave.Browser"
            case .edge: return "com.microsoft.edgemac"
            case .vivaldi: return "com.vivaldi.Vivaldi"
            case .arc: return "company.thebrowser.Browser"
            case .firefox: return "org.mozilla.firefox"
            }
        }

        var supportsCookieExtraction: Bool {
            // Currently we only support Safari and Chromium-based browsers
            switch self {
            case .safari, .chrome, .brave, .edge, .vivaldi:
                return true
            case .arc, .firefox:
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
            case .arc, .firefox:
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
}
