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
            throw GeminiError.missingAPIKey
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(apiKey)")!
        
        let prompt = """
        Analyze the following bank statement text. Extract all transactions and provide a summary.
        Follow these critical rules:
        1.  Identify every individual transaction.
        2.  For each transaction, extract: date (YYYY-MM-DD), description, amount (as a positive number), and currency (3-letter ISO code).
        3.  **Transaction Type:** Classify the type as 'income', 'expense', or 'internal'.
            - 'internal' is for transfers between the user's own accounts (e.g., "Transfer from Savings", "Payment to Credit Card from Checking"). These are not income or expenses.
        4.  **Categorization:** Assign a main 'category' and an optional 'subcategory'.
            - Example: For a payment to "Wolt", the category should be "Food" and subcategory should be "Delivery".
            - Example: For a salary, category: "Salary", no subcategory.
        5.  **Summary:** Calculate total income, total expenses, total internal transfers, net flow (income - expenses), primary currency, and the statement period (start/end dates).
        6.  Return the data strictly in JSON format matching this structure:
        {
          "transactions": [
            {
              "date": "YYYY-MM-DD",
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
        \(text)
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GeminiError.apiError("Failed to get response from Gemini API")
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = jsonResponse?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        // Очистка JSON от markdown code blocks если есть
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        }
        if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if cleanedText.hasSuffix("```") {
            cleanedText = String(cleanedText.dropLast(3))
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw GeminiError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(AnalysisResult.self, from: jsonData)
        
        // Generate IDs for transactions
        let transactionsWithIDs = result.transactions.map { transaction -> Transaction in
            let id = TransactionIDGenerator.generateID(for: transaction)
            return Transaction(
                id: id,
                date: transaction.date,
                time: nil,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                type: transaction.type,
                category: transaction.category,
                subcategory: transaction.subcategory,
                accountId: nil,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil
            )
        }
        
        return AnalysisResult(transactions: transactionsWithIDs, summary: result.summary)
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
