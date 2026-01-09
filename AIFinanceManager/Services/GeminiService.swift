//
//  GeminiService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

class GeminiService {
    static let shared = GeminiService()
    
    private var apiKey: String? {
        // Try Info.plist first
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist["GEMINI_API_KEY"] as? String,
           !key.isEmpty,
           key != "YOUR_GEMINI_API_KEY_HERE" {
            return key
        }
        
        // Try environment variable
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        
        return nil
    }
    
    private init() {}
    
    func analyzeTransactions(from text: String) async throws -> AnalysisResult {
        guard let apiKey = apiKey else {
            print("❌ Gemini API Key is missing")
            throw GeminiError.missingAPIKey
        }
        
        print("✅ Using Gemini API Key (length: \(apiKey.count))")
        
        // Проверяем, что текст не слишком большой
        let maxTextLength = 1000000 // ~1MB текста
        let textToAnalyze: String
        if text.count > maxTextLength {
            print("⚠️ Text is too long (\(text.count) chars), truncating to \(maxTextLength) chars")
            textToAnalyze = String(text.prefix(maxTextLength))
        } else {
            textToAnalyze = text
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(apiKey)")!
        print("📡 Sending request to Gemini API...")
        
        let prompt = """
        Analyze the following Alatau City Bank statement text. Extract all transactions and provide a summary.
        Follow these CRITICAL rules for Alatau City Bank statements:
        
        1.  **Transaction Identification:**
            - Identify every individual transaction from the statement
            - IGNORE "Код авторизации" (Authorization Code) - do not include it in description
            - IGNORE "Референс" (Reference) - do not include it in description
            - Extract only the merchant/vendor name from "Операция" and "Детали" columns
        
        2.  **Transaction Details:**
            - date (YYYY-MM-DD format, convert from DD.MM.YYYY if needed)
            - time (HH:mm format if available, otherwise null)
            - description: ONLY the merchant/vendor name from "Операция" or "Детали" column
              * IGNORE "Код авторизации" (Authorization Code) - do not include it
              * IGNORE "Референс" (Reference) - do not include it
              * Format: first letter uppercase, rest lowercase (e.g., "Yandex.go" not "YANDEX.GO", "Wolt" not "WOLT.COM", "Good Market" not "GOOD MARKET")
            - amount (as a positive number, use "Расход в валюте счета" for expenses, "Приход в валюте счета" for income)
            - currency (3-letter ISO code: KZT, USD, EUR, etc.)
        
        3.  **Transaction Type (CRITICAL):**
            - "Покупка" (Purchase) = 'expense' (расход)
            - "Пополнение" (Top-up/Deposit) = 'income' (доход)
            - "Перевод" (Transfer) = 'internal' (внутренний перевод)
            - "Снятия" (Withdrawal) = 'expense' (расход)
            - "Комиссия" (Fee) = 'expense' (расход)
        
        4.  **Categorization:**
            - Assign a main 'category' based on the merchant name
            - Use existing category names if they match (case-insensitive comparison)
            - If category doesn't exist, create a new one based on merchant type
            - Examples:
              * "Yandex.go" -> category: "Transport" (or existing similar category)
              * "Wolt" -> category: "Food" (or existing similar category)
              * "Good market" -> category: "Food" (or existing similar category)
              * "PlaystationNetwork" -> category: "Entertainment" (or existing similar category)
              * "Казахтелеком" -> category: "Utilities" (or existing similar category)
            - subcategory: optional, can be null
        
        5.  **Important:** 
            - Extract ALL transactions from ALL accounts (KZT, USD, EUR)
            - For transactions with different currency than account currency, use the converted amount from "Приход в валюте счета" or "Расход в валюте счета"
            - Ignore summary rows, totals, and header rows
            - Do not duplicate transactions
            - Format description: capitalize first letter, lowercase the rest (e.g., "Yandex.go", "Wolt", "Good market")
        
        6.  **Summary:** Calculate total income, total expenses, total internal transfers, net flow (income - expenses), primary currency, and the statement period (start/end dates).
        
        7.  Return the data strictly in JSON format matching this structure:
        {
          "transactions": [
            {
              "date": "YYYY-MM-DD",
              "time": "HH:mm" or null,
              "description": "string",
              "amount": number,
              "currency": "string",
              "type": "income" | "expense" | "internal",
              "category": "string",
              "subcategory": "string" (optional)
            }
          ],
          "summary": {
            "totalIncome": number,
            "totalExpenses": number,
            "totalInternalTransfers": number,
            "netFlow": number,
            "currency": "string",
            "startDate": "YYYY-MM-DD",
            "endDate": "YYYY-MM-DD"
          }
        }
        
        Statement Text:
        ---
        \(textToAnalyze)
        ---
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0,
                "responseMimeType": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("📤 Request body size: \(request.httpBody?.count ?? 0) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("📥 Response received, data size: \(data.count) bytes")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.apiError("Invalid response from server")
        }
        
        // Обработка HTTP ошибок
        guard httpResponse.statusCode == 200 else {
            let statusCode = httpResponse.statusCode
            var errorMessage = "HTTP \(statusCode): "
            
            // Пытаемся извлечь детали ошибки из ответа
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                // Специальная обработка для ошибки квоты
                if statusCode == 429 && (message.contains("quota") || message.contains("Quota exceeded") || message.contains("free_tier")) {
                    errorMessage = "Превышена квота Gemini API (бесплатный тариф). Проверьте лимиты на https://ai.google.dev/gemini-api/docs/rate-limits или перейдите на платный тариф."
                } else {
                    errorMessage += message
                }
            } else if let errorString = String(data: data, encoding: String.Encoding.utf8) {
                // Проверяем, содержит ли ответ информацию о квоте
                if statusCode == 429 && (errorString.contains("quota") || errorString.contains("Quota exceeded")) {
                    errorMessage = "Превышена квота Gemini API. Проверьте лимиты на https://ai.google.dev/gemini-api/docs/rate-limits"
                } else {
                    errorMessage += errorString
                }
            } else {
                switch statusCode {
                case 400:
                    errorMessage += "Bad Request - Check your API key and request format"
                case 401:
                    errorMessage += "Unauthorized - Invalid API key"
                case 403:
                    errorMessage += "Forbidden - API key may not have access to this model"
                case 429:
                    errorMessage = "Превышена квота Gemini API. Проверьте лимиты на https://ai.google.dev/gemini-api/docs/rate-limits"
                case 500...599:
                    errorMessage += "Server Error - Gemini API is temporarily unavailable"
                default:
                    errorMessage += "Unknown error"
                }
            }
            
            throw GeminiError.apiError(errorMessage)
        }
        
        // Парсим JSON ответ
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.invalidResponse
        }
        
        // Проверяем наличие ошибок в ответе
        if let error = jsonResponse["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw GeminiError.apiError(message)
        }
        
        guard let candidates = jsonResponse["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            // Проверяем, есть ли блокирующий контент
            if let candidates = jsonResponse["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let finishReason = firstCandidate["finishReason"] as? String,
               finishReason == "SAFETY" {
                throw GeminiError.apiError("Content was blocked by safety filters. Please try with a different statement.")
            }
            throw GeminiError.invalidResponse
        }
        
        // Очистка JSON от markdown code blocks если есть
        var cleanedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        }
        if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if cleanedText.hasSuffix("```") {
            cleanedText = String(cleanedText.dropLast(3))
        }
        cleanedText = cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard let jsonData = cleanedText.data(using: String.Encoding.utf8) else {
            print("❌ Failed to convert cleaned text to data")
            print("Cleaned text preview: \(String(cleanedText.prefix(500)))")
            throw GeminiError.invalidResponse
        }
        
        // Создаем промежуточную структуру для парсинга JSON с опциональным time
        struct ParsedTransaction: Codable {
            let date: String
            let time: String?
            let description: String
            let amount: Double
            let currency: String
            let type: TransactionType
            let category: String
            let subcategory: String?
        }
        
        struct ParsedSummary: Codable {
            let totalIncome: Double
            let totalExpenses: Double
            let totalInternalTransfers: Double
            let netFlow: Double
            let currency: String
            let startDate: String
            let endDate: String
            // plannedAmount не приходит от API, устанавливаем 0
        }
        
        struct ParsedAnalysisResult: Codable {
            let transactions: [ParsedTransaction]
            let summary: ParsedSummary
        }
        
        // Пытаемся декодировать JSON с детальной обработкой ошибок
        let parsedResult: ParsedAnalysisResult
        do {
            parsedResult = try JSONDecoder().decode(ParsedAnalysisResult.self, from: jsonData)
        } catch let decodingError as DecodingError {
            print("❌ JSON Decoding Error: \(decodingError)")
            print("JSON text preview: \(String(cleanedText.prefix(1000)))")
            
            // Пытаемся показать более понятную ошибку
            switch decodingError {
            case .keyNotFound(let key, let context):
                throw GeminiError.apiError("Ошибка парсинга ответа: отсутствует поле '\(key.stringValue)'. \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                throw GeminiError.apiError("Ошибка парсинга ответа: неверный тип для '\(context.codingPath.last?.stringValue ?? "unknown")'. Ожидался \(type).")
            case .valueNotFound(let type, let context):
                throw GeminiError.apiError("Ошибка парсинга ответа: отсутствует значение для '\(context.codingPath.last?.stringValue ?? "unknown")' типа \(type).")
            case .dataCorrupted(let context):
                throw GeminiError.apiError("Ошибка парсинга ответа: поврежденные данные. \(context.debugDescription)")
            @unknown default:
                throw GeminiError.apiError("Ошибка парсинга ответа от Gemini: \(decodingError.localizedDescription)")
            }
        } catch {
            print("❌ Unexpected decoding error: \(error)")
            throw GeminiError.apiError("Ошибка парсинга ответа: \(error.localizedDescription)")
        }
        
        // Generate IDs for transactions
        let transactionsWithIDs = parsedResult.transactions.map { parsed -> Transaction in
            let id = TransactionIDGenerator.generateID(
                date: parsed.date,
                description: parsed.description,
                amount: parsed.amount,
                type: parsed.type,
                currency: parsed.currency
            )
            return Transaction(
                id: id,
                date: parsed.date,
                time: parsed.time,
                description: parsed.description,
                amount: parsed.amount,
                currency: parsed.currency,
                type: parsed.type,
                category: parsed.category,
                subcategory: parsed.subcategory,
                accountId: nil,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil
            )
        }
        
        // Конвертируем ParsedSummary в Summary
        let summary = Summary(
            totalIncome: parsedResult.summary.totalIncome,
            totalExpenses: parsedResult.summary.totalExpenses,
            totalInternalTransfers: parsedResult.summary.totalInternalTransfers,
            netFlow: parsedResult.summary.netFlow,
            currency: parsedResult.summary.currency,
            startDate: parsedResult.summary.startDate,
            endDate: parsedResult.summary.endDate,
            plannedAmount: 0 // API не возвращает это значение
        )
        
        return AnalysisResult(transactions: transactionsWithIDs, summary: summary)
    }
}

enum GeminiError: LocalizedError {
    case missingAPIKey
    case apiError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is missing. Please set GEMINI_API_KEY in Info.plist or environment variables."
        case .apiError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from Gemini API"
        }
    }
}
