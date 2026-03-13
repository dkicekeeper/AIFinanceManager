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

    // Explicit Codable implementation with nonisolated to avoid MainActor isolation warnings.
    // Format matches Swift's synthesis: {"sfSymbol": {"_0": "name"}} etc.
    private enum CodingKeys: String, CodingKey {
        case sfSymbol, bankLogo, brandService
    }
    private enum AssocCodingKeys: String, CodingKey { case _0 }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.sfSymbol) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            self = .sfSymbol(try nested.decode(String.self, forKey: ._0))
        } else if container.contains(.bankLogo) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .bankLogo)
            self = .bankLogo(try nested.decode(BankLogo.self, forKey: ._0))
        } else if container.contains(.brandService) {
            let nested = try container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            self = .brandService(try nested.decode(String.self, forKey: ._0))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown IconSource case"))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sfSymbol(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .sfSymbol)
            try nested.encode(name, forKey: ._0)
        case .bankLogo(let logo):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .bankLogo)
            try nested.encode(logo, forKey: ._0)
        case .brandService(let name):
            var nested = container.nestedContainer(keyedBy: AssocCodingKeys.self, forKey: .brandService)
            try nested.encode(name, forKey: ._0)
        }
    }

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
