import XCTest
@testable import SmartHome

final class CredentialVaultTests: XCTestCase {
    func testRememberedLoginSurvivesReloadAndCanBeCleared() throws {
        let name = "vault-test-" + UUID().uuidString
        let vault = CredentialVault(account: name)
        defer { vault.clear() }
        XCTAssertNil(vault.read())
        let expected = RememberedLogin(username: "sample-user", password: "sample-password")
        try vault.save(expected)
        XCTAssertEqual(CredentialVault(account: name).read(), expected)
        vault.clear()
        XCTAssertNil(CredentialVault(account: name).read())
    }
    func testUpdatingCredentialsReplacesPreviousPassword() throws {
        let vault = CredentialVault(account: "vault-update-" + UUID().uuidString)
        defer { vault.clear() }
        try vault.save(RememberedLogin(username: "sample", password: "first"))
        let updated = RememberedLogin(username: "sample", password: "second")
        try vault.save(updated)
        XCTAssertEqual(vault.read(), updated)
    }
}
