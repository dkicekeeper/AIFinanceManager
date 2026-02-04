//
//  SettingsStorageService.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Service for loading and saving settings
/// Handles UserDefaults persistence with validation
@MainActor
final class SettingsStorageService: SettingsStorageServiceProtocol {
    private let userDefaults: UserDefaults
    private let validator: SettingsValidationServiceProtocol

    private static let userDefaultsKey = "appSettings"

    init(
        userDefaults: UserDefaults = .standard,
        validator: SettingsValidationServiceProtocol = SettingsValidationService()
    ) {
        self.userDefaults = userDefaults
        self.validator = validator
    }

    // MARK: - SettingsStorageServiceProtocol

    func loadSettings() async throws -> AppSettings {
        #if DEBUG
        print("⚙️ [SettingsStorageService] Loading settings")
        #endif

        // Try to load from UserDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey) {
            do {
                let settings = try JSONDecoder().decode(AppSettings.self, from: data)

                // Validate loaded settings
                try validator.validateSettings(settings)

                #if DEBUG
                print("✅ [SettingsStorageService] Settings loaded and validated")
                #endif

                return settings
            } catch {
                #if DEBUG
                print("⚠️ [SettingsStorageService] Failed to decode or validate settings: \(error)")
                print("   Creating default settings")
                #endif

                // Return default on decode/validation failure
                return AppSettings.makeDefault()
            }
        }

        #if DEBUG
        print("ℹ️ [SettingsStorageService] No saved settings found, creating default")
        #endif

        return AppSettings.makeDefault()
    }

    func saveSettings(_ settings: AppSettings) async throws {
        #if DEBUG
        print("⚙️ [SettingsStorageService] Saving settings")
        #endif

        // Validate before save
        do {
            try validator.validateSettings(settings)
        } catch {
            #if DEBUG
            print("❌ [SettingsStorageService] Validation failed: \(error)")
            #endif
            throw error
        }

        // Encode and save
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: Self.userDefaultsKey)

            #if DEBUG
            print("✅ [SettingsStorageService] Settings saved successfully")
            #endif
        } catch {
            #if DEBUG
            print("❌ [SettingsStorageService] Failed to encode settings: \(error)")
            #endif
            throw SettingsStorageError.saveFailed(underlying: error)
        }
    }

    func validateSettings(_ settings: AppSettings) throws {
        try validator.validateSettings(settings)
    }
}
