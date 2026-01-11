//
//  ContentView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import PDFKit

struct ContentView: View {
    @StateObject private var viewModel = TransactionsViewModel()
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedAccount: Account?
    @State private var showingVoiceInput = false
    @State private var showingVoiceConfirmation = false
    @State private var parsedOperation: ParsedOperation?
    @StateObject private var voiceService = VoiceInputService()
    @State private var showingTimeFilter = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var recognizedText: String? = nil
    @State private var structuredRows: [[String]]? = nil
    @State private var showingRecognizedText = false
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil

    // Кешированные данные для производительности
    @State private var cachedSummary: Summary?
    
    var body: some View {
        NavigationView {
            ScrollView {
            VStack(spacing: AppSpacing.lg) {
                accountsSection
                    .screenPadding()

                if !viewModel.allTransactions.isEmpty {
                    NavigationLink(destination: HistoryView(viewModel: viewModel, initialCategory: nil)
                        .environmentObject(timeFilterManager)) {
                        analyticsCard
                            .screenPadding()
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                NavigationLink(destination: SubscriptionsListView(viewModel: viewModel)
                    .environmentObject(timeFilterManager)) {
                    subscriptionsCard
                        .screenPadding()
                }
                .buttonStyle(PlainButtonStyle())

                QuickAddTransactionView(viewModel: viewModel)
                    .screenPadding()

                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        if let progress = ocrProgress {
                            ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                                Text("Распознавание текста: страница \(progress.current) из \(progress.total)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text("Страница \(progress.current) из \(progress.total)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView("Обработка PDF...")
                        }
                    }
                    .padding(AppSpacing.md)
                }

                if let error = viewModel.errorMessage {
                    ErrorMessageView(message: error)
                        .screenPadding()
                }
            }
                .padding(.vertical, AppSpacing.md)
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    selectedFileURL = url
                    Task {
                        await analyzePDF(url: url)
                    }
                }
            }
            .sheet(isPresented: $showingRecognizedText) {
                if let text = recognizedText, !text.isEmpty {
                    RecognizedTextView(
                        recognizedText: text,
                        structuredRows: structuredRows,
                        viewModel: viewModel,
                        onImport: { csvFile in
                            showingRecognizedText = false
                            recognizedText = nil
                            structuredRows = nil
                            // Открываем CSVPreviewView для продолжения импорта
                            showingCSVPreview = true
                            parsedCSVFile = csvFile
                        },
                        onCancel: {
                            showingRecognizedText = false
                            recognizedText = nil
                            structuredRows = nil
                            viewModel.isLoading = false
                        }
                    )
                } else {
                    // Fallback - показываем пустой экран, если текст не загружен
                    NavigationView {
                        VStack {
                            Text("Ошибка загрузки текста")
                                .font(.headline)
                            Text("Попробуйте еще раз")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCSVPreview) {
                if let csvFile = parsedCSVFile {
                    CSVPreviewView(csvFile: csvFile, viewModel: viewModel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingTimeFilter = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(timeFilterManager.currentFilter.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $selectedAccount) { account in
                AccountActionView(viewModel: viewModel, account: account)
                    .environmentObject(timeFilterManager)
            }
            .sheet(isPresented: $showingVoiceInput) {
                VoiceInputView(voiceService: voiceService) { transcribedText in
                    showingVoiceInput = false
                    // Парсим текст синхронно
                    let parser = VoiceInputParser(
                        accounts: viewModel.accounts,
                        categories: viewModel.customCategories,
                        subcategories: viewModel.subcategories,
                        defaultAccount: viewModel.accounts.first
                    )
                    let parsed = parser.parse(transcribedText)
                    // Устанавливаем parsedOperation синхронно перед открытием sheet
                    parsedOperation = parsed
                    // Открываем sheet сразу после установки parsedOperation
                    showingVoiceConfirmation = true
                }
            }
            .sheet(isPresented: $showingVoiceConfirmation) {
                if let parsed = parsedOperation {
                    VoiceInputConfirmationView(
                        viewModel: viewModel,
                        parsedOperation: parsed,
                        originalText: voiceService.getFinalText()
                    )
                }
            }
            .sheet(isPresented: $showingTimeFilter) {
                TimeFilterView(filterManager: timeFilterManager)
            }
            .safeAreaInset(edge: .bottom) {
                // Primary actions: голос и загрузка выписок (liquid glass стиль iOS 16+)
                HStack(spacing: AppSpacing.xl) {
                    // Кнопка голосового ввода
                    Button(action: {
                        showingVoiceInput = true
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 64, height: 64)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    }

                    // Кнопка загрузки выписок
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 64, height: 64)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                PerformanceProfiler.start("ContentView.onAppear")
                updateSummary()
                PerformanceProfiler.end("ContentView.onAppear")
            }
            .onChange(of: viewModel.allTransactions.count) { _, _ in
                updateSummary()
            }
            .onChange(of: timeFilterManager.currentFilter) { _, _ in
                updateSummary()
            }
        }
    }

    // Обновление кешированного summary
    private func updateSummary() {
        PerformanceProfiler.start("ContentView.updateSummary")
        cachedSummary = viewModel.summary(timeFilterManager: timeFilterManager)
        PerformanceProfiler.end("ContentView.updateSummary")
    }
    
    private var timeFilterButton: some View {
        Button(action: {
            showingTimeFilter = true
        }) {
            HStack {
                Image(systemName: "calendar")
                Text(timeFilterManager.currentFilter.displayName)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
    }
    
    private var accountsSection: some View {
        HStack {
            if viewModel.accounts.isEmpty {
                Text("Нет счетов")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.accounts) { account in
                            Button(action: {
                                selectedAccount = account
                            }) {
                                HStack(spacing: 8) {
                                    account.bankLogo.image(size: 32)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name)
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                        Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .padding(10)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    private var subscriptionsCard: some View {
        SubscriptionsCardView(viewModel: viewModel)
    }
    
    private var analyticsCard: some View {
        // Используем кешированный summary вместо повторного вызова viewModel.summary()
        guard let summary = cachedSummary else {
            return AnyView(EmptyView())
        }

        let currency = viewModel.appSettings.baseCurrency
        let total = summary.totalExpenses + summary.totalIncome
        let expensePercent = total > 0 ? (summary.totalExpenses / total) : 0.0
        let incomePercent = total > 0 ? (summary.totalIncome / total) : 0.0

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Суммы сверху
            HStack {
                Text(Formatting.formatCurrency(summary.totalExpenses, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text(Formatting.formatCurrency(summary.totalIncome, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            
            // Одна полоса, где расходы и доходы толкают друг друга
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Расходы слева
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * expensePercent)
                    
                    // Доходы справа
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * incomePercent)
                    
                    // Пустое пространство
                    Spacer()
                }
                .cornerRadius(4)
            }
            .frame(height: 8)
            
            // В планах
            if summary.plannedAmount > 0 {
                HStack {
                    Text("В планах")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(Formatting.formatCurrency(summary.plannedAmount, currency: currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .cardStyle())
    }
    
    
    private func analyzePDF(url: URL) async {
        print("📄 Starting PDF analysis for: \(url.path)")
        
        await MainActor.run {
            viewModel.isLoading = true
            viewModel.errorMessage = nil
            ocrProgress = nil
            recognizedText = nil
        }
        
        do {
            // Извлекаем текст через PDFKit или OCR
            print("📖 Extracting text from PDF...")
            let ocrResult = try await PDFService.shared.extractText(from: url) { current, total in
                // Callback уже вызывается на MainActor в PDFService
                print("📊 OCR Progress: \(current)/\(total)")
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }
            
            print("✅ Text extracted: \(ocrResult.fullText.count) characters")
            
            // Проверяем, что текст не пустой
            let trimmedText = ocrResult.fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                print("❌ Extracted text is empty")
                await MainActor.run {
                    viewModel.errorMessage = "Не удалось извлечь текст из PDF. Возможно, документ поврежден или пуст."
                    viewModel.isLoading = false
                    ocrProgress = nil
                }
                return
            }
            
            // Показываем распознанный текст для проверки пользователем на MainActor
            print("📝 Showing recognized text modal...")
            if let structuredRows = ocrResult.structuredRows {
                print("📊 Structured rows found: \(structuredRows.count) rows")
            } else {
                print("⚠️ No structured rows found, will use text parsing")
            }
            
            await MainActor.run {
                recognizedText = ocrResult.fullText
                structuredRows = ocrResult.structuredRows
                ocrProgress = nil
                viewModel.isLoading = false
                showingRecognizedText = true
                print("✅ Modal should be shown, showingRecognizedText = \(showingRecognizedText), recognizedText length = \(recognizedText?.count ?? 0), structuredRows count = \(structuredRows?.count ?? 0)")
            }
            
        } catch let error as PDFError {
            let errorMessage = error.localizedDescription
            print("❌ PDF Error: \(errorMessage)")
            await MainActor.run {
                viewModel.errorMessage = errorMessage
                viewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        } catch {
            print("❌ General Error: \(error.localizedDescription)")
            await MainActor.run {
                viewModel.errorMessage = "Ошибка при распознавании: \(error.localizedDescription)"
                viewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        }
    }
    
}

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
                    Text("Распознанный текст")
                        .font(.headline)
                    Text("Текст успешно распознан. Вы можете импортировать транзакции или скопировать текст.")
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
                                parseErrorMessage = "Не удалось найти транзакции в структурированных данных. Возможно, формат выписки отличается от ожидаемого."
                            } else {
                                parseErrorMessage = "Не удалось найти транзакции в распознанном тексте. Убедитесь, что текст содержит таблицу транзакций выписки."
                            }
                            showingParseError = true
                        } else {
                            // Импортируем
                            print("✅ Найдено \(csvFile.rows.count) транзакций для импорта")
                            onImport(csvFile)
                        }
                    }) {
                        Label("Импортировать транзакции", systemImage: "square.and.arrow.down")
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
                            Label("Копировать", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                        
                        Button(action: onCancel) {
                            Text("Закрыть")
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
            .navigationTitle("Текст выписки")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isParsing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Парсинг выписки...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
            .alert("Текст скопирован", isPresented: $showingCopyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Распознанный текст скопирован в буфер обмена.")
            }
            .alert("Ошибка парсинга", isPresented: $showingParseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(parseErrorMessage)
            }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(Formatting.formatCurrency(amount, currency: currency))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AppIconSize.md))
            Text(message)
                .font(AppTypography.body)
        }
        .padding(AppSpacing.md)
        .background(Color.red.opacity(0.1))
        .foregroundColor(.red)
        .cornerRadius(AppRadius.sm)
    }
}

#Preview {
    ContentView()
}
