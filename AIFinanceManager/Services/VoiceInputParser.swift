//
//  VoiceInputParser.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import Combine

class VoiceInputParser {
    private let accounts: [Account]
    private let categories: [CustomCategory]
    private let subcategories: [Subcategory]
    private let defaultAccount: Account?
    
    // Словарь замен для нормализации
    private let textReplacements: [String: String] = [
        // Варианты "со счета"
        "со счёта": "со счета",
        "с счета": "со счета",
        "с счёта": "со счета",
        // Варианты валюты
        "тэг": "тг",
        "тенга": "тг",
        "тенг": "тг",
        // Бренды/счета
        "каспи": "kaspi",
        "каспи банк": "kaspi",
        "kaspi bank": "kaspi",
        "халик": "halyk",
        "халик банк": "halyk",
        "halyk bank": "halyk",
        "алатау": "alatau",
        "алатау сити": "alatau",
        "alatau city": "alatau",
        "хом кредит": "home credit",
        "хомкредит": "home credit",
        "home credit bank": "home credit",
        "жусан": "jusan",
        "jusan bank": "jusan"
    ]
    
    // Алиасы для счетов
    private let accountAliases: [String: [String]] = [
        "kaspi": ["каспи", "kaspi", "каспи банк", "kaspi bank", "каспи карта"],
        "halyk": ["halyk", "халик", "halyk bank", "халик банк", "халик карта"],
        "alatau": ["alatau", "алатау", "alatau city", "алатау сити", "алатау карта"],
        "home credit": ["home credit", "хом кредит", "хомкредит", "home credit bank"],
        "jusan": ["jusan", "жусан", "jusan bank", "жусан банк"],
        "gold": ["gold", "голд", "gold card", "голд карта"]
    ]
    
    // Стоп-слова для поиска счета
    private let stopWords: Set<String> = ["с", "со", "счет", "счёта", "счета", "карта", "карты", "банк", "банка"]
    
    // Словарь для распознавания чисел словами
    private let numberWords: [String: Int] = [
        "ноль": 0, "нуль": 0,
        "один": 1, "одна": 1, "одно": 1,
        "два": 2, "две": 2,
        "три": 3,
        "четыре": 4,
        "пять": 5,
        "шесть": 6,
        "семь": 7,
        "восемь": 8,
        "девять": 9,
        "десять": 10,
        "одиннадцать": 11,
        "двенадцать": 12,
        "тринадцать": 13,
        "четырнадцать": 14,
        "пятнадцать": 15,
        "шестнадцать": 16,
        "семнадцать": 17,
        "восемнадцать": 18,
        "девятнадцать": 19,
        "двадцать": 20,
        "тридцать": 30,
        "сорок": 40,
        "пятьдесят": 50,
        "шестьдесят": 60,
        "семьдесят": 70,
        "восемьдесят": 80,
        "девяносто": 90,
        "сто": 100,
        "двести": 200,
        "триста": 300,
        "четыреста": 400,
        "пятьсот": 500,
        "шестьсот": 600,
        "семьсот": 700,
        "восемьсот": 800,
        "девятьсот": 900,
        "тысяча": 1000, "тысячи": 1000, "тысяч": 1000
    ]
    
    init(accounts: [Account], categories: [CustomCategory], subcategories: [Subcategory], defaultAccount: Account?) {
        self.accounts = accounts
        self.categories = categories
        self.subcategories = subcategories
        self.defaultAccount = defaultAccount
    }
    
    func parse(_ text: String) -> ParsedOperation {
        #if DEBUG
        print("🔍 [VoiceInputParser] Исходный текст: \"\(text)\"")
        #endif
        
        let normalizedText = normalizeText(text)
        
        #if DEBUG
        print("🔍 [VoiceInputParser] Нормализованный текст: \"\(normalizedText)\"")
        #endif
        
        var operation = ParsedOperation(note: text)
        
        // 1. Определяем дату
        operation.date = parseDate(from: normalizedText)
        
        // 2. Определяем тип операции
        operation.type = parseType(from: normalizedText)
        
        // 3. Извлекаем сумму
        operation.amount = parseAmount(from: normalizedText)
        
        #if DEBUG
        if let amount = operation.amount {
            print("🔍 [VoiceInputParser] Распознанная сумма: \(amount)")
        } else {
            print("🔍 [VoiceInputParser] Сумма не распознана")
        }
        #endif
        
        // 4. Извлекаем валюту
        operation.currencyCode = parseCurrency(from: normalizedText)
        
        #if DEBUG
        if let currency = operation.currencyCode {
            print("🔍 [VoiceInputParser] Распознанная валюта: \(currency)")
        }
        #endif
        
        // 5. Ищем счет
        let accountResult = findAccount(from: normalizedText)
        operation.accountId = accountResult.accountId
        
        #if DEBUG
        if let accountId = accountResult.accountId,
           let account = accounts.first(where: { $0.id == accountId }) {
            print("🔍 [VoiceInputParser] Выбранный счет: \(account.name) (ID: \(accountId))")
            print("🔍 [VoiceInputParser] Причина выбора: \(accountResult.reason)")
        } else {
            print("🔍 [VoiceInputParser] Счет не распознан")
        }
        #endif
        
        // 6. Определяем категорию и подкатегории
        let (category, subcats) = parseCategory(from: normalizedText)
        operation.categoryName = category
        operation.subcategoryNames = subcats
        
        #if DEBUG
        if let categoryName = category {
            print("🔍 [VoiceInputParser] Выбранная категория: \(categoryName)")
            if !subcats.isEmpty {
                print("🔍 [VoiceInputParser] Выбранные подкатегории: \(subcats.joined(separator: ", "))")
            }
        }
        #endif
        
        // Если валюта не найдена, используем валюту найденного счета или счета по умолчанию
        if operation.currencyCode == nil {
            if let accountId = operation.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                operation.currencyCode = account.currency
            } else if let defaultAccount = defaultAccount {
                operation.currencyCode = defaultAccount.currency
            } else {
                operation.currencyCode = "KZT" // По умолчанию тенге
            }
        }
        
        // Если счет не найден, используем счет по умолчанию
        if operation.accountId == nil {
            operation.accountId = defaultAccount?.id
        }
        
        return operation
    }
    
    // MARK: - Private Methods
    
    private func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Применяем замены
        for (from, to) in textReplacements {
            normalized = normalized.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        
        // Collapse spaces (убираем множественные пробелы)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 1. Парсинг даты
    private func parseDate(from text: String) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if text.contains("сегодня") {
            return today
        } else if text.contains("вчера") {
            return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        
        return today
    }
    
    // 2. Парсинг типа операции
    private func parseType(from text: String) -> TransactionType {
        let expenseKeywords = [
            "потратил", "потратила", "потратили", "потратило",
            "заплатил", "заплатила", "заплатили", "заплатило",
            "купил", "купила", "купили", "купило",
            "расход", "расходы",
            "оплатил", "оплатила", "оплатили",
            "списал", "списала", "списали",
            "покупка", "покупки"
        ]
        let incomeKeywords = [
            "получил", "получила", "получили", "получило",
            "пришло", "пришла", "пришли",
            "заработал", "заработала", "заработали",
            "доход", "доходы",
            "пополнил", "пополнила", "пополнили",
            "пополнение", "пополнения",
            "начислил", "начислила", "начислили"
        ]
        
        for keyword in expenseKeywords {
            if text.contains(keyword) {
                return .expense
            }
        }
        
        for keyword in incomeKeywords {
            if text.contains(keyword) {
                return .income
            }
        }
        
        return .expense // По умолчанию расход
    }
    
    // 3. Парсинг суммы (с поддержкой слов)
    private func parseAmount(from text: String) -> Decimal? {
        // Сначала пытаемся найти число через regex
        let patterns = [
            // Число с валютой перед числом
            #"(?:тенге|тг|₸|доллар|долларов|\$|usd|евро|eur|€|рубл|rub|₽)\s*(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)"#,
            // Число с валютой после числа
            #"(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)\s*(?:тенге|тг|₸|доллар|долларов|\$|usd|евро|eur|€|рубл|rub|₽)"#,
            // Просто число (ищем самое большое число)
            #"\b(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)\b"#
        ]
        
        var foundAmounts: [(Decimal, Int)] = [] // (amount, length) для сортировки
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: text) {
                        let amountString = String(text[range])
                            .replacingOccurrences(of: ",", with: ".")
                            .replacingOccurrences(of: " ", with: "") // Убираем пробелы в числах типа "10 000"
                            .trimmingCharacters(in: .whitespaces)
                        
                        if let amount = Decimal(string: amountString) {
                            foundAmounts.append((amount, amountString.count))
                        }
                    }
                }
            }
        }
        
        // Если нашли числа через regex, выбираем самое большое
        if let largestAmount = foundAmounts.max(by: { $0.0 < $1.0 }) {
            let amount = largestAmount.0
            let rounded = (amount as NSDecimalNumber).rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            return rounded as Decimal
        }
        
        // Если не нашли через regex, пытаемся распознать словами
        return parseAmountFromWords(text)
    }
    
    // Парсинг суммы словами (до 9999)
    private func parseAmountFromWords(_ text: String) -> Decimal? {
        let words = text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        
        var result = 0
        var currentNumber = 0
        var hasThousand = false
        
        for word in words {
            let lowercased = word.lowercased()
            
            if let number = numberWords[lowercased] {
                if number == 1000 {
                    if currentNumber > 0 {
                        result += currentNumber * 1000
                        currentNumber = 0
                    } else {
                        result += 1000
                    }
                    hasThousand = true
                } else if number >= 100 {
                    if currentNumber > 0 {
                        result += currentNumber
                    }
                    currentNumber = number
                } else if number >= 10 {
                    if currentNumber >= 100 {
                        currentNumber += number
                    } else {
                        if currentNumber > 0 {
                            result += currentNumber
                        }
                        currentNumber = number
                    }
                } else {
                    if currentNumber >= 10 {
                        currentNumber += number
                    } else {
                        currentNumber = currentNumber * 10 + number
                    }
                }
            } else if lowercased == "тысяч" || lowercased == "тысячи" || lowercased == "тысяча" {
                if currentNumber > 0 {
                    result += currentNumber * 1000
                    currentNumber = 0
                } else if result == 0 {
                    result = 1000
                }
                hasThousand = true
            }
        }
        
        if currentNumber > 0 {
            if hasThousand {
                result += currentNumber
            } else {
                result += currentNumber
            }
        }
        
        if result > 0 && result <= 9999 {
            return Decimal(result)
        }
        
        return nil
    }
    
    // 4. Парсинг валюты
    private func parseCurrency(from text: String) -> String? {
        let currencyMap: [String: String] = [
            "тенге": "KZT",
            "тг": "KZT",
            "₸": "KZT",
            "доллар": "USD",
            "долларов": "USD",
            "usd": "USD",
            "$": "USD",
            "евро": "EUR",
            "eur": "EUR",
            "€": "EUR",
            "рубл": "RUB",
            "rub": "RUB"
        ]
        
        for (keyword, code) in currencyMap {
            if text.contains(keyword) {
                return code
            }
        }
        
        return nil
    }
    
    // Результат поиска счета
    private struct AccountSearchResult {
        let accountId: String?
        let reason: String
    }
    
    // 5. Поиск счета по тексту (с токенизацией и скорингом)
    private func findAccount(from text: String) -> AccountSearchResult {
        // Паттерны для поиска счета
        let patterns = [
            #"со\s+счета\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"со\s+счёта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+карты\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счета"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счёта"#,
            #"карта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счет\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счёт\s+([^,\s]+(?:\s+[^,\s]+)*)"#
        ]
        
        var accountName: String?
        
        // Пытаемся найти по паттернам
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                accountName = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // Токенизация текста (убираем стоп-слова)
        let textTokens = tokenize(text)
        
        // Скоринг счетов
        var accountScores: [(Account, Int, String)] = [] // (account, score, reason)
        
        for account in accounts {
            let normalizedAccountName = normalizeText(account.name)
            let accountTokens = tokenize(normalizedAccountName)
            
            var score = 0
            var reason = ""
            
            // Проверяем алиасы
            for (key, aliases) in accountAliases {
                if normalizedAccountName.contains(key) {
                    for alias in aliases {
                        if text.contains(alias) {
                            score += 10
                            reason = "Найден по алиасу '\(alias)'"
                            break
                        }
                    }
                }
            }
            
            // Точное совпадение имени
            if text.contains(normalizedAccountName) {
                score += 20
                if reason.isEmpty {
                    reason = "Точное совпадение имени"
                }
            }
            
            // Совпадение токенов
            let matchingTokens = accountTokens.filter { token in
                textTokens.contains(token) && !stopWords.contains(token)
            }
            if !matchingTokens.isEmpty {
                score += matchingTokens.count * 5
                if reason.isEmpty {
                    reason = "Совпадение токенов: \(matchingTokens.joined(separator: ", "))"
                }
            }
            
            // Если нашли по паттерну
            if let accountName = accountName, normalizedAccountName.contains(normalizeText(accountName)) {
                score += 30
                reason = "Найден по паттерну: '\(accountName)'"
            }
            
            if score > 0 {
                accountScores.append((account, score, reason))
            }
        }
        
        // Сортируем по скору
        accountScores.sort { $0.1 > $1.1 }
        
        // Если есть несколько кандидатов с близким скором (разница < 5), возвращаем nil для выбора на confirm
        if accountScores.count >= 2 {
            let bestScore = accountScores[0].1
            let secondScore = accountScores[1].1
            if bestScore - secondScore < 5 {
                return AccountSearchResult(
                    accountId: nil,
                    reason: "Несколько кандидатов с близким скором: \(accountScores[0].0.name) (\(bestScore)) vs \(accountScores[1].0.name) (\(secondScore))"
                )
            }
        }
        
        if let bestMatch = accountScores.first {
            return AccountSearchResult(accountId: bestMatch.0.id, reason: bestMatch.2)
        }
        
        return AccountSearchResult(accountId: nil, reason: "Счет не найден")
    }
    
    // Токенизация текста (удаление стоп-слов)
    private func tokenize(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }
    
    // 6. Парсинг категории и подкатегорий (сначала подкатегории, потом категории)
    private func parseCategory(from text: String) -> (category: String?, subcategories: [String]) {
        // Словарь синонимов для категорий и подкатегорий
        let categoryMap: [String: (category: String, subcategory: String?)] = [
            // Транспорт - сначала подкатегории
            "такси": ("Transport", "Taxi"),
            "uber": ("Transport", "Taxi"),
            "yandex": ("Transport", "Taxi"),
            "яндекс": ("Transport", "Taxi"),
            "бензин": ("Transport", "Gas"),
            "заправка": ("Transport", "Gas"),
            "парковка": ("Transport", "Parking"),
            "автобус": ("Transport", nil),
            "метро": ("Transport", nil),
            "проезд": ("Transport", nil),
            "транспорт": ("Transport", nil),
            
            // Еда - синонимы
            "кафе": ("Food", nil),
            "кофе": ("Food", "Coffee"), // Синоним кафе
            "ресторан": ("Food", nil),
            "обед": ("Food", nil),
            "ужин": ("Food", nil),
            "завтрак": ("Food", nil),
            "еда": ("Food", nil),
            "столовая": ("Food", nil),
            "доставка": ("Food", "Delivery"),
            "еда доставка": ("Food", "Delivery"),
            
            // Продукты
            "продукты": ("Groceries", nil),
            "магазин": ("Shopping", nil),
            "супермаркет": ("Groceries", nil),
            "гипермаркет": ("Groceries", nil),
            
            // Покупки
            "покупка": ("Shopping", nil),
            "шопинг": ("Shopping", nil),
            "одежда": ("Shopping", "Clothing"),
            "обувь": ("Shopping", "Clothing"),
            
            // Развлечения
            "кино": ("Entertainment", nil),
            "театр": ("Entertainment", nil),
            "концерт": ("Entertainment", nil),
            "развлечения": ("Entertainment", nil),
            
            // Здоровье
            "аптека": ("Health", "Pharmacy"),
            "лекарство": ("Health", "Pharmacy"),
            "врач": ("Health", "Doctor"),
            "больница": ("Health", "Doctor"),
            "стоматолог": ("Health", "Dentist"),
            
            // Коммунальные
            "коммунальные": ("Utilities", nil),
            "квартплата": ("Utilities", nil),
            "электричество": ("Utilities", "Electricity"),
            "вода": ("Utilities", "Water"),
            "газ": ("Utilities", "Gas"),
            "интернет": ("Utilities", "Internet"),
            "телефон": ("Utilities", "Phone"),
            
            // Образование
            "образование": ("Education", nil),
            "школа": ("Education", nil),
            "университет": ("Education", nil),
            "курсы": ("Education", nil),
            
            // Другое
            "услуги": ("Services", nil),
            "ремонт": ("Services", nil)
        ]
        
        // Сначала ищем подкатегории, потом категории
        var foundSubcategories: [String] = []
        var foundCategory: String?
        
        for (keyword, (category, subcategory)) in categoryMap {
            if text.contains(keyword) {
                // Сначала проверяем подкатегорию
                if let subcategory = subcategory {
                    let matchingSubcategory = subcategories.first { normalizeText($0.name) == normalizeText(subcategory) }
                    if let matchingSubcategory = matchingSubcategory {
                        foundSubcategories.append(matchingSubcategory.name)
                    }
                }
                
                // Затем категорию
                if foundCategory == nil {
                    let matchingCategory = categories.first { normalizeText($0.name) == normalizeText(category) }
                    foundCategory = matchingCategory?.name ?? category
                }
                
                // Если нашли и подкатегорию и категорию, можно выйти
                if !foundSubcategories.isEmpty && foundCategory != nil {
                    break
                }
            }
        }
        
        // Если не нашли, возвращаем "Другое"
        if foundCategory == nil {
            foundCategory = categories.first { normalizeText($0.name) == normalizeText("Другое") }?.name ?? "Другое"
        }
        
        return (foundCategory, foundSubcategories)
    }
}
