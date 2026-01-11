//
//  AppSettings.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

class AppSettings: ObservableObject, Codable {
    @Published var baseCurrency: String = "KZT"
    @Published var wallpaperImageName: String? = nil

    enum CodingKeys: String, CodingKey {
        case baseCurrency
        case wallpaperImageName
    }

    init(baseCurrency: String = "KZT", wallpaperImageName: String? = nil) {
        self.baseCurrency = baseCurrency
        self.wallpaperImageName = wallpaperImageName
    }

    // MARK: - Codable

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

    // MARK: - Persistence

    private static let userDefaultsKey = "appSettings"

    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.userDefaultsKey)
        }
    }

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return AppSettings()
    }
}

// Доступные валюты для выбора
extension AppSettings {
    static let availableCurrencies = ["KZT", "USD", "EUR", "RUB", "GBP", "CNY", "JPY"]
}
