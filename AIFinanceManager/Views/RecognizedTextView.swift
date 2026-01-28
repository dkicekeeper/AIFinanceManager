//
//  RecognizedTextView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct RecognizedTextView: View {
    let recognizedText: String
    let structuredRows: [[String]]?
    let viewModel: TransactionsViewModel
    let onImport: (CSVFile) -> Void
    let onCancel: () -> Void
    @State private var showingCopyAlert = false
    @State private var isParsing = false
    @State private var showingParseError = false
    @State private var parseErrorMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Заголовок
                VStack(spacing: 8) {
                    Text(String(localized: "modal.recognizedText.title"))
                        .font(.headline)
                    Text(String(localized: "modal.recognizedText.message"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))

                // Текст
                ScrollView {
                    Text(recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled) // Позволяет копировать текст
                }

                // Кнопки
                VStack(spacing: 12) {
                    // Основная кнопка - импорт транзакций
                    Button(action: {
                        isParsing = true
                        HapticManager.success()

                        // Парсим текст выписки в CSV формат с использованием структурированных данных
                        print("🔍 Парсинг выписки: structuredRows count = \(structuredRows?.count ?? 0)")
                        let csvFile = StatementTextParser.parseStatementToCSV(recognizedText, structuredRows: structuredRows)

                        isParsing = false

                        if csvFile.rows.isEmpty {
                            // Если не найдено транзакций, показываем ошибку
                            if structuredRows != nil {
                                parseErrorMessage = String(localized: "error.noTransactionsStructured")
                            } else {
                                parseErrorMessage = String(localized: "error.noTransactionsFound")
                            }
                            showingParseError = true
                        } else {
                            // Импортируем
                            print("✅ Найдено \(csvFile.rows.count) транзакций для импорта")
                            onImport(csvFile)
                        }
                    }) {
                        Label(String(localized: "transaction.importTransactions"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(isParsing)

                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = recognizedText
                            showingCopyAlert = true
                            HapticManager.success()
                        }) {
                            Label(String(localized: "button.copy"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }

                        Button(action: onCancel) {
                            Text(String(localized: "button.close"))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "navigation.statementText"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isParsing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView(String(localized: "progress.parsingStatement"))
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
            .alert(String(localized: "alert.textCopied.title"), isPresented: $showingCopyAlert) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "alert.textCopied.message"))
            }
            .alert(String(localized: "alert.parseError.title"), isPresented: $showingParseError) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(parseErrorMessage)
            }
        }
    }
}
