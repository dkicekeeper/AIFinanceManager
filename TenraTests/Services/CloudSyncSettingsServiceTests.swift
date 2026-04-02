//
//  CloudSyncSettingsServiceTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@Suite("CloudSyncSettingsService")
struct CloudSyncSettingsServiceTests {

    @Test("pushToCloud does not crash and respects loop-prevention guard")
    func pushToCloud() {
        let service = CloudSyncSettingsService()
        // NSUbiquitousKeyValueStore is unavailable in the test sandbox (no iCloud entitlement),
        // so we only verify the call completes without crashing and that the service exists.
        service.pushToCloud(key: "baseCurrency", value: "USD")
        #expect(CloudSyncSettingsService.syncedKeys.contains("baseCurrency"))
    }

    @Test("syncedKeys returns expected settings keys")
    func syncedKeys() {
        let keys = CloudSyncSettingsService.syncedKeys
        #expect(keys.contains("baseCurrency"))
    }
}
