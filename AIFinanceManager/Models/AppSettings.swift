//
//  AppSettings.swift
//  AIFinanceManager
//
//  Created on 2024
//  Enhanced: 2026-02-04 (Settings Refactoring Phase 1)
//

import Foundation
import SwiftUI
import Combine

/// Application settings model
/// Enhanced with validation, defaults, and factory methods
class AppSettings: ObservableObject, Codable {
    // MARK: - Published Properties

    @Published var baseCurrency: String
    @Published var wallpaperImageName: String?

    // MARK: - Constants

    static let defaultCurrency = "KZT"
    static let availableCurrencies = ["KZT", "USD", "EUR", "RUB", "GBP", "CNY", "JPY"]

    // MARK: - Computed Properties

    /// Validate if current settings are valid
    var isValid: Bool {
        Self.availableCurrencies.contains(baseCurrency)
    }

    // MARK: - Initialization

    init(
        baseCurrency: String = defaultCurrency,
        wallpaperImageName: String? = nil
    ) {
        self.baseCurrency = baseCurrency
        self.wallpaperImageName = wallpaperImageName
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case baseCurrency
        case wallpaperImageName
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCurrency = try container.decode(String.self, forKey: .baseCurrency)
        wallpaperImageName = try container.decodeIfPresent(String.self, forKey: .wallpaperImageName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseCurrency, forKey: .baseCurrency)
        try container.encodeIfPresent(wallpaperImageName, forKey: .wallpaperImageName)
    }

    // MARK: - Factory Methods

    /// Create default settings instance
    static func makeDefault() -> AppSettings {
        AppSettings(
            baseCurrency: defaultCurrency,
            wallpaperImageName: nil
        )
    }

    // MARK: - Legacy Persistence (Deprecated)
    // NOTE: These methods are kept for backward compatibility
    // New code should use SettingsStorageService instead

    private static let userDefaultsKey = "appSettings"

    /// Legacy save method
    /// - Note: Prefer using SettingsStorageService for new code
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.userDefaultsKey)
        }
    }

    /// Legacy load method
    /// - Note: Prefer using SettingsStorageService for new code
    /// - Returns: AppSettings instance (default if load fails)
    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return makeDefault()
    }
}
