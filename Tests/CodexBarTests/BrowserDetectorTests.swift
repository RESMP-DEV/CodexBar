import CodexBarCore
import Testing

@Suite
struct BrowserDetectorTests {
    @Test
    func browserPriorityComparison() {
        // Default browser with cookies should win
        let defaultWithCookies = BrowserDetector.BrowserPriority(
            browser: .chrome,
            isDefault: true,
            hasCookies: true,
            cookieAge: 100)

        let nonDefaultWithCookies = BrowserDetector.BrowserPriority(
            browser: .safari,
            isDefault: false,
            hasCookies: true,
            cookieAge: 50)

        #expect(defaultWithCookies > nonDefaultWithCookies)
    }

    @Test
    func browserWithCookiesWinsOverNoCookies() {
        let withCookies = BrowserDetector.BrowserPriority(
            browser: .safari,
            isDefault: false,
            hasCookies: true,
            cookieAge: 100)

        let withoutCookies = BrowserDetector.BrowserPriority(
            browser: .chrome,
            isDefault: false,
            hasCookies: false,
            cookieAge: nil)

        #expect(withCookies > withoutCookies)
    }

    @Test
    func moreRecentCookiesWin() {
        let recent = BrowserDetector.BrowserPriority(
            browser: .chrome,
            isDefault: false,
            hasCookies: true,
            cookieAge: 50) // 50 seconds old

        let older = BrowserDetector.BrowserPriority(
            browser: .safari,
            isDefault: false,
            hasCookies: true,
            cookieAge: 1000) // 1000 seconds old

        #expect(recent > older)
    }

    @Test
    func safariPreferredWhenEqual() {
        let safari = BrowserDetector.BrowserPriority(
            browser: .safari,
            isDefault: false,
            hasCookies: false,
            cookieAge: nil)

        let chrome = BrowserDetector.BrowserPriority(
            browser: .chrome,
            isDefault: false,
            hasCookies: false,
            cookieAge: nil)

        #expect(safari > chrome)
    }

    @Test
    func supportedBrowsersList() {
        // Safari and Chromium browsers should be supported
        #expect(BrowserDetector.Browser.safari.supportsCookieExtraction)
        #expect(BrowserDetector.Browser.chrome.supportsCookieExtraction)
        #expect(BrowserDetector.Browser.brave.supportsCookieExtraction)
        #expect(BrowserDetector.Browser.edge.supportsCookieExtraction)
        #expect(BrowserDetector.Browser.vivaldi.supportsCookieExtraction)
        
        // Firefox browsers should be supported
        #expect(BrowserDetector.Browser.firefox.supportsCookieExtraction)
        #expect(BrowserDetector.Browser.firefoxDeveloperEdition.supportsCookieExtraction)

        // Arc is not yet supported
        #expect(!BrowserDetector.Browser.arc.supportsCookieExtraction)
    }

    @Test
    func browserBundleIdentifiers() {
        #expect(BrowserDetector.Browser.safari.bundleIdentifier == "com.apple.Safari")
        #expect(BrowserDetector.Browser.chrome.bundleIdentifier == "com.google.Chrome")
        #expect(BrowserDetector.Browser.brave.bundleIdentifier == "com.brave.Browser")
        #expect(BrowserDetector.Browser.edge.bundleIdentifier == "com.microsoft.edgemac")
        #expect(BrowserDetector.Browser.arc.bundleIdentifier == "company.thebrowser.Browser")
        #expect(BrowserDetector.Browser.firefox.bundleIdentifier == "org.mozilla.firefox")
        #expect(BrowserDetector.Browser.firefoxDeveloperEdition.bundleIdentifier == "org.mozilla.firefoxdeveloperedition")
    }
}
