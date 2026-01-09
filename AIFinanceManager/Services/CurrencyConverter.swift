//
//  CurrencyConverter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

class CurrencyConverter {
    private static let baseURL = "https://nationalbank.kz/rss/get_rates.cfm"
    private static var cachedRates: [String: Double] = [:]
    private static var cacheDate: Date?
    private static let cacheValidityHours: TimeInterval = 24 * 60 * 60 // 24 часа
    
    // Получить курс валюты к тенге
    static func getExchangeRate(for currency: String) async -> Double? {
        // KZT всегда равен 1
        if currency == "KZT" {
            return 1.0
        }
        
        // Проверяем кэш
        if let cachedDate = cacheDate,
           Date().timeIntervalSince(cachedDate) < cacheValidityHours,
           let cachedRate = cachedRates[currency] {
            return cachedRate
        }
        
        // Загружаем курсы с Нацбанка РК
        guard let url = URL(string: baseURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Парсим XML
            let parser = XMLParser(data: data)
            let delegate = ExchangeRateParserDelegate()
            parser.delegate = delegate
            parser.parse()
            
            // Обновляем кэш
            cachedRates = delegate.rates
            cacheDate = Date()
            
            return delegate.rates[currency]
        } catch {
            print("Ошибка загрузки курсов валют: \(error)")
            // Возвращаем кэшированное значение, если есть
            return cachedRates[currency]
        }
    }
    
    // Конвертировать сумму из одной валюты в другую
    static func convert(amount: Double, from: String, to: String) async -> Double? {
        // Если валюты одинаковые, возвращаем сумму без изменений
        if from == to {
            return amount
        }
        
        // Получаем курсы обеих валют к тенге
        guard let fromRate = await getExchangeRate(for: from),
              let toRate = await getExchangeRate(for: to) else {
            return nil
        }
        
        // Конвертируем через тенге: amount * (toRate / fromRate)
        let converted = amount * (toRate / fromRate)
        return converted
    }
    
    // Получить все доступные курсы
    static func getAllRates() async -> [String: Double] {
        _ = await getExchangeRate(for: "USD") // Загружаем курсы
        return cachedRates
    }
}

// MARK: - XML Parser Delegate
private class ExchangeRateParserDelegate: NSObject, XMLParserDelegate {
    var rates: [String: Double] = [:]
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        switch currentElement {
        case "title":
            currentTitle += trimmed
        case "description":
            currentDescription += trimmed
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // Парсим курс из title и description
            // Формат: title содержит название валюты, description содержит курс
            if !currentTitle.isEmpty && !currentDescription.isEmpty {
                // Ищем код валюты в title (например, "USD", "EUR")
                let currencyCodes = ["USD", "EUR", "RUB", "GBP", "CNY", "JPY", "KGS", "UZS"]
                for code in currencyCodes {
                    if currentTitle.uppercased().contains(code) {
                        if let rate = Double(currentDescription.replacingOccurrences(of: ",", with: ".")) {
                            rates[code] = rate
                        }
                        break
                    }
                }
            }
            currentTitle = ""
            currentDescription = ""
        }
        currentElement = ""
    }
}
