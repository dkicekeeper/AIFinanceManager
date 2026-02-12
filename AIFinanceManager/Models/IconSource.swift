//
//  IconSource.swift
//  AIFinanceManager
//
//  Unified icon/logo source model for all entities
//

import Foundation

/// Универсальный источник иконки/логотипа для всех сущностей (счета, подписки, категории)
enum IconSource: Codable, Equatable, Hashable {
    case sfSymbol(String)           // SF Symbol иконка
    case bankLogo(BankLogo)         // Локальный банковский логотип из Assets
    case brandService(String)       // Логотип бренда через logo.dev API

    /// Строковый идентификатор для сохранения (legacy compatibility)
    var displayIdentifier: String {
        switch self {
        case .sfSymbol(let name):
            return "sf:\(name)"
        case .bankLogo(let logo):
            return "bank:\(logo.rawValue)"
        case .brandService(let name):
            return "brand:\(name)"
        }
    }

    /// Парсинг из строкового идентификатора (для миграции старых данных)
    static func from(displayIdentifier: String) -> IconSource? {
        if displayIdentifier.hasPrefix("sf:") {
            let name = String(displayIdentifier.dropFirst(3))
            return .sfSymbol(name)
        } else if displayIdentifier.hasPrefix("bank:") {
            let rawValue = String(displayIdentifier.dropFirst(5))
            if let logo = BankLogo(rawValue: rawValue) {
                return .bankLogo(logo)
            }
        } else if displayIdentifier.hasPrefix("brand:") {
            let name = String(displayIdentifier.dropFirst(6))
            return .brandService(name)
        }
        return nil
    }

    /// Миграция из старых полей модели (brandLogo, brandId, brandName)
    /// Используется для обновления существующих данных при первом запуске
    static func migrate(
        bankLogo: BankLogo?,
        brandId: String?,
        brandName: String?
    ) -> IconSource? {
        // Приоритет: bankLogo > brandId > brandName
        if let bankLogo = bankLogo, bankLogo != .none {
            return .bankLogo(bankLogo)
        }

        if let brandId = brandId, !brandId.isEmpty {
            return from(displayIdentifier: brandId)
        }

        if let brandName = brandName, !brandName.isEmpty {
            return .brandService(brandName)
        }

        return nil
    }
}
