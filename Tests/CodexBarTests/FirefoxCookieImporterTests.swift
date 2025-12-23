import CodexBarCore
import Testing

@Suite
struct FirefoxCookieImporterTests {
    @Test
    func domainNormalization() {
        // Test that leading dots are stripped
        let records = [
            FirefoxCookieImporter.CookieRecord(
                host: ".example.com",
                name: "test",
                path: "/",
                value: "value",
                expiry: 0,
                isSecure: false,
                isHTTPOnly: false),
        ]
        
        let cookies = FirefoxCookieImporter.makeHTTPCookies(records)
        #expect(cookies.count == 1)
        #expect(cookies.first?.domain == "example.com")
    }

    @Test
    func cookieConversion() {
        let records = [
            FirefoxCookieImporter.CookieRecord(
                host: "chatgpt.com",
                name: "session",
                path: "/",
                value: "test123",
                expiry: 1735689600, // Jan 1, 2025
                isSecure: true,
                isHTTPOnly: true),
        ]
        
        let cookies = FirefoxCookieImporter.makeHTTPCookies(records)
        #expect(cookies.count == 1)
        
        guard let cookie = cookies.first else { return }
        #expect(cookie.name == "session")
        #expect(cookie.value == "test123")
        #expect(cookie.isSecure)
        #expect(cookie.domain == "chatgpt.com")
        #expect(cookie.path == "/")
    }

    @Test
    func httponlyCookieProperties() {
        let records = [
            FirefoxCookieImporter.CookieRecord(
                host: "example.com",
                name: "httponly-cookie",
                path: "/",
                value: "secret",
                expiry: 0,
                isSecure: false,
                isHTTPOnly: true),
        ]
        
        let cookies = FirefoxCookieImporter.makeHTTPCookies(records)
        #expect(cookies.count == 1)
        
        guard let cookie = cookies.first else { return }
        #expect(cookie.name == "httponly-cookie")
        #expect(cookie.isHTTPOnly)
    }

    @Test
    func originURLForDifferentDomains() {
        // This is tested indirectly through cookie conversion
        let openaiRecord = FirefoxCookieImporter.CookieRecord(
            host: "openai.com",
            name: "test",
            path: "/",
            value: "val",
            expiry: 0,
            isSecure: false,
            isHTTPOnly: false)
        
        let chatgptRecord = FirefoxCookieImporter.CookieRecord(
            host: "chatgpt.com",
            name: "test",
            path: "/",
            value: "val",
            expiry: 0,
            isSecure: false,
            isHTTPOnly: false)
        
        let claudeRecord = FirefoxCookieImporter.CookieRecord(
            host: "claude.ai",
            name: "test",
            path: "/",
            value: "val",
            expiry: 0,
            isSecure: false,
            isHTTPOnly: false)
        
        let cookies = FirefoxCookieImporter.makeHTTPCookies([openaiRecord, chatgptRecord, claudeRecord])
        #expect(cookies.count == 3)
    }
}
