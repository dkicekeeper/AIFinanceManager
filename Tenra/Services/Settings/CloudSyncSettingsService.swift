//
//  CloudSyncSettingsService.swift
//  Tenra
//
//  Wraps NSUbiquitousKeyValueStore for syncing user preferences across devices.
//  Loop prevention: applySyncedSettings() writes ONLY to UserDefaults.
//  pushToCloud() is called ONLY from explicit user actions.
//

import Foundation
import os

final class CloudSyncSettingsService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudSyncSettingsService")

    static let syncedKeys: [String] = [
        "baseCurrency",
        "homeBackgroundMode",
        "blurWallpaper"
    ]

    var onRemoteSettingsChanged: (([String: Any]) -> Void)?

    private var isApplyingRemoteChanges = false
    private var observer: Any?

    init() {}

    deinit {
        stopListening()
    }

    // MARK: - Outgoing

    func pushToCloud(key: String, value: Any) {
        guard !isApplyingRemoteChanges else {
            CloudSyncSettingsService.logger.debug("Skipping pushToCloud during remote apply for key: \(key)")
            return
        }
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func pushAllToCloud() {
        for key in Self.syncedKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                NSUbiquitousKeyValueStore.default.set(value, forKey: key)
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - Incoming

    func startListening() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func stopListening() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        guard reasonRaw == NSUbiquitousKeyValueStoreServerChange ||
              reasonRaw == NSUbiquitousKeyValueStoreInitialSyncChange else {
            return
        }

        var changedSettings: [String: Any] = [:]
        for key in Self.syncedKeys {
            if let value = NSUbiquitousKeyValueStore.default.object(forKey: key) {
                changedSettings[key] = value
            }
        }

        guard !changedSettings.isEmpty else { return }

        CloudSyncSettingsService.logger.info("Received \(changedSettings.count) remote settings changes")

        isApplyingRemoteChanges = true
        for (key, value) in changedSettings {
            UserDefaults.standard.set(value, forKey: key)
        }
        isApplyingRemoteChanges = false

        onRemoteSettingsChanged?(changedSettings)
    }
}
