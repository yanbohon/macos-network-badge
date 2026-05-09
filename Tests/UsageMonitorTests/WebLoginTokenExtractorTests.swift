import XCTest
@testable import UsageMonitor

final class WebLoginTokenExtractorTests: XCTestCase {
    func testExtractsCapturedLoginEnvelopeFromWebStorage() throws {
        let captured = """
        {"code":0,"message":"success","data":{"access_token":"web-token","refresh_token":"web-refresh","expires_in":7200,"token_type":"Bearer","user":{"id":7,"email":"web@example.com","balance":42.5,"status":"active"}}}
        """

        let token = try XCTUnwrap(WebLoginTokenExtractor.extract(from: [
            WebLoginTokenExtractor.capturedAuthStorageKey: captured,
        ], cookies: [:]))

        XCTAssertEqual(token.accessToken, "web-token")
        XCTAssertEqual(token.refreshToken, "web-refresh")
        XCTAssertEqual(token.expiresIn, 7200)
        XCTAssertEqual(token.user?.email, "web@example.com")
        XCTAssertEqual(token.user?.balance, 42.5)
    }

    func testFallsBackToTokenKeysInStorageAndCookies() throws {
        let token = try XCTUnwrap(WebLoginTokenExtractor.extract(from: [
            "token": "storage-token",
        ], cookies: [
            "refresh_token": "cookie-refresh",
        ]))

        XCTAssertEqual(token.accessToken, "storage-token")
        XCTAssertEqual(token.refreshToken, "cookie-refresh")
        XCTAssertNil(token.user)
    }

    func testIgnoresBlankAndMalformedValues() {
        XCTAssertNil(WebLoginTokenExtractor.extract(from: [
            WebLoginTokenExtractor.capturedAuthStorageKey: "not json",
            "access_token": " ",
        ], cookies: [:]))
    }
}
