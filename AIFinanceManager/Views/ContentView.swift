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
    @State private var wallpaperImage: UIImage? = nil
    @State private var isDarkWallpaper: Bool = false
    
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

                        QuickAddTransactionView(viewModel: viewModel, adaptiveTextColor: adaptiveTextColor)
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
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                // Primary actions: голос и загрузка выписок (liquid glass стиль iOS 16+)
                HStack(spacing: AppSpacing.xl) {
                    // Кнопка голосового ввода
                    Button(action: {
                        showingVoiceInput = true
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(adaptiveTextColor)
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
                            .foregroundStyle(adaptiveTextColor)
                            .frame(width: 64, height: 64)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .background {
                // Wallpaper фон - должен покрывать весь экран, включая область под safeAreaInset
                if let wallpaperImage = wallpaperImage {
                    Image(uiImage: wallpaperImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea(.all, edges: .all)
                } else {
                    // Базовый фон как везде
                    Color.clear
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
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
            .onAppear {
                PerformanceProfiler.start("ContentView.onAppear")
                updateSummary()
                loadWallpaper()
                // Очищаем фон NavigationView через UIKit
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                PerformanceProfiler.end("ContentView.onAppear")
            }
            .onChange(of: viewModel.allTransactions.count) { _, _ in
                updateSummary()
            }
            .onChange(of: timeFilterManager.currentFilter) { _, _ in
                updateSummary()
            }
            .onChange(of: viewModel.appSettings.wallpaperImageName) { _, _ in
                loadWallpaper()
            }
        }
    }

    // Обновление кешированного summary
    private func updateSummary() {
        PerformanceProfiler.start("ContentView.updateSummary")
        cachedSummary = viewModel.summary(timeFilterManager: timeFilterManager)
        PerformanceProfiler.end("ContentView.updateSummary")
    }
    
    // Загрузка обоев (асинхронно для производительности)
    private func loadWallpaper() {
        Task.detached(priority: .userInitiated) {
            guard let wallpaperName = await MainActor.run(body: { viewModel.appSettings.wallpaperImageName }) else {
                await MainActor.run {
                    wallpaperImage = nil
                    isDarkWallpaper = false
                }
                return
            }

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(wallpaperName)

            // Проверяем существование файла
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let image = UIImage(contentsOfFile: fileURL.path) else {
                await MainActor.run {
                    wallpaperImage = nil
                    isDarkWallpaper = false
                }
                return
            }

            // Вычисляем яркость в background thread для производительности
            let isDark = ImageBrightnessCalculator.isDark(image)

            // Обновляем UI на главном потоке
            await MainActor.run {
                wallpaperImage = image
                isDarkWallpaper = isDark
            }
        }
    }
    
    // Адаптивный цвет текста в зависимости от яркости обоев
    private var adaptiveTextColor: Color {
        if wallpaperImage != nil {
            return isDarkWallpaper ? .white : .black
        }
        // Если нет обоев, используем системный цвет
        return Color(UIColor.label)
    }
    

    private var accountsSection: some View {
        HStack {
            if viewModel.accounts.isEmpty {
                Text("Нет счетов")
                    .font(.subheadline)
                    .foregroundStyle(adaptiveTextColor)
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
                                        .foregroundStyle(adaptiveTextColor.opacity(0.7))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name)
                                            .font(.title3)
                                            .foregroundStyle(adaptiveTextColor)
                                        Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(adaptiveTextColor)
                                    }
                                }
                                .padding(16)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    // Граница для глубины
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.1)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                }
                                .overlay(Color.white.opacity(0.001))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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

        return AnyView(VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("История")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(adaptiveTextColor)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(adaptiveTextColor)
            }
            
            // Прогресс-бар с суммами под ним
            VStack(spacing: 8) {
                // Прогресс-бар
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Расходы слева
                        if expensePercent > 0 {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: geometry.size.width * expensePercent)
                        }
                        
                        // Доходы справа
                        if incomePercent > 0 {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: geometry.size.width * incomePercent)
                        }
                        
                        // Пустое пространство
                        Spacer()
                    }
                    .cornerRadius(6)
                }
                .frame(height: 12)
                
                // Суммы под прогресс-баром
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
            }
            
            // В планах
            if summary.plannedAmount > 0 {
                HStack {
                    Text("В планах")
                        .font(.subheadline)
                        .foregroundStyle(adaptiveTextColor)
                    
                    Spacer()
                    
                    Text(Formatting.formatCurrency(summary.plannedAmount, currency: currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            // Граница для глубины
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(Color.white.opacity(0.001))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5))
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
        .environmentObject(TimeFilterManager())
}
