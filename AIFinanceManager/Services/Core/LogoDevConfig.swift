//
//  LogoDevConfig.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

/// Модель результата поиска logo.dev
struct LogoSearchResult: Codable, Identifiable {
    let id: String
    let name: String
    let domain: String?
    let logo: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case domain
        case logo
    }
}

/// Ответ от Search API logo.dev
struct LogoSearchResponse: Codable {
    let results: [LogoSearchResult]?
    let data: [LogoSearchResult]? // Альтернативное поле для результатов
    let items: [LogoSearchResult]? // Еще один возможный вариант
    
    // Пытаемся декодировать как массив напрямую
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Пробуем декодировать как массив
        if let array = try? container.decode([LogoSearchResult].self) {
            self.results = array
            self.data = nil
            self.items = nil
            return
        }
        
        // Пробуем декодировать как объект
        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.results = try keyedContainer.decodeIfPresent([LogoSearchResult].self, forKey: .results)
        self.data = try keyedContainer.decodeIfPresent([LogoSearchResult].self, forKey: .data)
        self.items = try keyedContainer.decodeIfPresent([LogoSearchResult].self, forKey: .items)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(items, forKey: .items)
    }
    
    enum CodingKeys: String, CodingKey {
        case results
        case data
        case items
    }
    
    var allResults: [LogoSearchResult] {
        results ?? data ?? items ?? []
    }
}

/// Конфигурация для logo.dev API
enum LogoDevConfig {
    /// Получает public key из Info.plist (nonisolated для использования из любого контекста)
    private nonisolated static var publicKey: String? {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let key = plist["LOGO_DEV_PUBLIC_KEY"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }
    
    /// Проверяет, доступен ли сервис (есть public key)
    nonisolated static var isAvailable: Bool {
        publicKey != nil
    }
    
    /// Формирует URL для загрузки логотипа
    /// - Parameter brandName: Название бренда или домен
    /// - Returns: URL для загрузки логотипа или nil, если ключ отсутствует
    nonisolated static func logoURL(for brandName: String) -> URL? {
        guard let key = publicKey else {
            return nil
        }
        
        // Нормализуем brandName: убираем пробелы по краям
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalizedName.isEmpty else {
            return nil
        }
        
        // Percent encoding для безопасного URL
        guard let encodedBrandName = normalizedName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        
        // Формируем URL: https://img.logo.dev/{name}?token={key}
        let urlString = "https://img.logo.dev/\(encodedBrandName)?token=\(key)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        #if DEBUG
        #endif
        
        return url
    }
    
    /// Формирует URL для Search API
    /// - Parameter query: Поисковый запрос (название бренда)
    /// - Returns: URL для поиска или nil, если ключ отсутствует
    nonisolated static func searchURL(for query: String) -> URL? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return nil
        }
        
        // Percent encoding для query параметра
        guard let encodedQuery = normalizedQuery
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Формируем URL: https://logo.dev/api/search?name={query}
        // Токен будет добавлен в заголовке Authorization
        let urlString = "https://logo.dev/api/search?name=\(encodedQuery)"
        
        return URL(string: urlString)
    }
    
    /// Получает токен для использования в запросах
    nonisolated static var token: String? {
        publicKey
    }
}
