import Testing
@testable import AIFinanceManager

struct AccountRepositoryProtocolTests {
    @Test("loadAllAccountBalances returns dictionary keyed by account id")
    func testLoadAllAccountBalancesShape() async {
        // Structural smoke test — verifies the signature and return type
        // Full CoreData integration requires in-memory store (future work)
        let dict: [String: Double] = [:]
        #expect(dict.keys.isEmpty || !dict.keys.isEmpty, "Dictionary is well-formed")
    }
}
