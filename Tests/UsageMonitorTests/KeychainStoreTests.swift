import LocalAuthentication
import Security
import XCTest
@testable import UsageMonitor

final class KeychainStoreTests: XCTestCase {
    func testLookupQueriesDisableSystemAuthenticationUI() {
        let store = KeychainStore(service: "test.service")

        assertDisablesSystemAuthenticationUI(store.readQuery(for: .accessToken))
        assertDisablesSystemAuthenticationUI(store.updateQuery(for: .accessToken))
        assertDisablesSystemAuthenticationUI(store.deleteQuery(for: .accessToken))
    }

    private func assertDisablesSystemAuthenticationUI(
        _ query: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let context = query[kSecUseAuthenticationContext as String] as? LAContext

        XCTAssertEqual(context?.interactionNotAllowed, true, file: file, line: line)
        XCTAssertEqual(query["u_AuthUI"] as? String, "u_AuthUIF", file: file, line: line)
    }
}
