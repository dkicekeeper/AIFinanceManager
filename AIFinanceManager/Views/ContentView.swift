import SwiftUI
import PDFKit

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var timeFilterManager: TimeFilterManager

    // @State для принудительного обновления UI при изменении данных
    @State private var refreshTrigger: Int = 0
    @State private var isInitializing = true

    // Computed properties для доступа к ViewModels из coordinator
    // CRITICAL: SwiftUI не отслеживает изменения в nested computed properties автоматически!
    // Поэтому мы используем onChange observers и refreshTrigger для принудительного обновления
    private var viewModel: TransactionsViewModel {
        coordinator.transactionsViewModel
    }
    private var accountsViewModel: AccountsViewModel {
        coordinator.accountsViewModel
    }
    private var categoriesViewModel: CategoriesViewModel {
        coordinator.categoriesViewModel
    }
    private var subscriptionsViewModel: SubscriptionsViewModel {
        coordinator.subscriptionsViewModel
    }
    @State private var showingFilePicker = false
    @State private var selectedAccount: Account?
    @State private var showingVoiceInput = false
    @State private var parsedOperation: ParsedOperation?
    @StateObject private var voiceService = VoiceInputService()
    @State private var showingTimeFilter = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var recognizedText: String? = nil
    @State private var structuredRows: [[String]]? = nil
    @State private var showingRecognizedText = false
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil
    @State private var showingAddAccount = false

    // Wallpaper image
    @State private var wallpaperImage: UIImage? = nil
    
    private var scrollContent: some View {
        VStack(spacing: AppSpacing.lg) {
            accountsSection

            historyNavigationLink
            
            subscriptionsNavigationLink

            categoriesSection

            if viewModel.isLoading {
                loadingProgressView
            }

            if let error = viewModel.errorMessage {
                ErrorMessageView(message: error)
                    .screenPadding()
            }
        }
        .padding(.vertical, AppSpacing.md)
    }
    
    private var historyNavigationLink: some View {
        NavigationLink(destination: HistoryView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            initialCategory: nil
        )
            .environmentObject(timeFilterManager)) {
            analyticsCard
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }
    
    private var subscriptionsNavigationLink: some View {
        NavigationLink(destination: SubscriptionsListView(
            subscriptionsViewModel: subscriptionsViewModel,
            transactionsViewModel: viewModel
        )
            .environmentObject(timeFilterManager)) {
            subscriptionsCard
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }
    
    private var loadingProgressView: some View {
        VStack(spacing: AppSpacing.md) {
            if let progress = ocrProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                    Text(String(localized: "progress.recognizingText", defaultValue: "Recognizing text: page \(progress.current) of \(progress.total)"))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
                Text(String(localized: "progress.page", defaultValue: "Page \(progress.current) of \(progress.total)"))
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            } else {
                ProgressView(String(localized: "progress.processingPDF"))
            }
        }
        .padding(AppSpacing.md)
    }
    
    private var bottomActions: some View {
        HStack(spacing: AppSpacing.xl) {
            // Кнопка голосового ввода
            Button(action: {
                showingVoiceInput = true
            }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(String(localized: "accessibility.voiceInput"))
            .accessibilityHint(String(localized: "accessibility.voiceInputHint"))
            
            // Кнопка загрузки выписок
            Button(action: {
                showingFilePicker = true
            }) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(String(localized: "accessibility.importStatement"))
            .accessibilityHint(String(localized: "accessibility.importStatementHint"))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ScrollView {
                    scrollContent
                }
                .safeAreaInset(edge: .bottom) {
                    bottomActions
                }
                .opacity(isInitializing ? 0 : 1)
                
                // Simple loading overlay
                if isInitializing {
                    VStack(spacing: AppSpacing.lg) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(String(localized: "progress.loadingData", defaultValue: "Loading data..."))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                // Initialize coordinator asynchronously on first appearance
                if isInitializing {
                    await coordinator.initialize()
                    withAnimation {
                        isInitializing = false
                    }
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
                            Text(String(localized: "error.loadTextFailed"))
                                .font(.headline)
                            Text(String(localized: "error.tryAgain"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCSVPreview) {
                if let csvFile = parsedCSVFile {
                    CSVPreviewView(
                        csvFile: csvFile,
                        transactionsViewModel: viewModel,
                        categoriesViewModel: categoriesViewModel
                    )
                }
            }
            .toolbar {
                toolbarContent
            }
            .sheet(item: $selectedAccount) { account in
                accountSheet(for: account)
            }
            .sheet(isPresented: $showingVoiceInput) {
                voiceInputSheet
            }
            .sheet(item: $parsedOperation) { parsed in
                VoiceInputConfirmationView(
                    transactionsViewModel: viewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    parsedOperation: parsed,
                    originalText: voiceService.getFinalText()
                )
            }
            .sheet(isPresented: $showingTimeFilter) {
                TimeFilterView(filterManager: timeFilterManager)
            }
            .sheet(isPresented: $showingAddAccount) {
                AccountEditView(
                    accountsViewModel: accountsViewModel,
                    transactionsViewModel: viewModel,
                    account: nil,
                    onSave: { account in
                        HapticManager.success()
                        accountsViewModel.addAccount(name: account.name, balance: account.balance, currency: account.currency, bankLogo: account.bankLogo)
                        viewModel.syncAccountsFrom(accountsViewModel)
                        showingAddAccount = false
                    },
                    onCancel: { showingAddAccount = false }
                )
            }
            .onAppear {
                PerformanceProfiler.start("ContentView.onAppear")
                loadWallpaper()

                // Setup VoiceInputService with ViewModels for contextual strings (iOS 17+)
                voiceService.categoriesViewModel = categoriesViewModel
                voiceService.accountsViewModel = accountsViewModel

                PerformanceProfiler.end("ContentView.onAppear")
            }
            .onChange(of: viewModel.allTransactions.count) { oldValue, newValue in
                refreshTrigger += 1
            }
            .onChange(of: accountsViewModel.accounts.count) { oldValue, newValue in
                refreshTrigger += 1
            }
            .onChange(of: accountsViewModel.accounts) { _, _ in
                refreshTrigger += 1
            }
            .onChange(of: timeFilterManager.currentFilter) { _, _ in
                // Summary will be recomputed automatically in analyticsCard
                refreshTrigger += 1
            }
            .onChange(of: viewModel.appSettings.wallpaperImageName) { _, _ in
                loadWallpaper()
            }
            .id(refreshTrigger) // Принудительное обновление всего view при изменении refreshTrigger
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingTimeFilter = true
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "calendar")
                        Text(timeFilterManager.currentFilter.displayName)
                            .font(AppTypography.bodySmall)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.primary)
                }
                .accessibilityLabel(String(localized: "accessibility.calendar"))
                .accessibilityHint(String(localized: "accessibility.calendarHint"))
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView(
                    transactionsViewModel: viewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    subscriptionsViewModel: subscriptionsViewModel,
                    depositsViewModel: coordinator.depositsViewModel
                )) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(String(localized: "accessibility.settings"))
                .accessibilityHint(String(localized: "accessibility.settingsHint"))
            }
        }
    }
    
    @ViewBuilder
    private func accountSheet(for account: Account) -> some View {
        Group {
            if account.isDeposit {
                NavigationView {
                    DepositDetailView(
                        depositsViewModel: coordinator.depositsViewModel,
                        transactionsViewModel: viewModel,
                        accountId: account.id
                    )
                        .environmentObject(timeFilterManager)
                }
            } else {
                AccountActionView(
                    transactionsViewModel: viewModel,
                    accountsViewModel: accountsViewModel,
                    account: account
                )
                    .environmentObject(timeFilterManager)
            }
        }
    }
    
    private var voiceInputSheet: some View {
        // Создаем parser один раз для всего sheet
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: viewModel
        )

        return VoiceInputView(
            voiceService: voiceService,
            onComplete: { transcribedText in
                // Проверяем, что текст не пустой
                guard !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    // Если текст пустой, просто закрываем voice input
                    showingVoiceInput = false
                    return
                }
                
                showingVoiceInput = false
                let parsed = parser.parse(transcribedText)
                // Устанавливаем parsedOperation - sheet откроется автоматически через .sheet(item:)
                parsedOperation = parsed
            },
            parser: parser
        )
    }

    
    // Загрузка обоев (асинхронно для производительности)
    private func loadWallpaper() {
        Task.detached(priority: .userInitiated) {
            guard let wallpaperName = await MainActor.run(body: { viewModel.appSettings.wallpaperImageName }) else {
                await MainActor.run {
                    wallpaperImage = nil
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
                }
                return
            }

            // Обновляем UI на главном потоке
            await MainActor.run {
                wallpaperImage = image
            }
        }
    }
    

    private var accountsSection: some View {
        Group {
            if accountsViewModel.accounts.isEmpty {
                Button(action: {
                    HapticManager.light()
                    showingAddAccount = true
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(String(localized: "accounts.title", defaultValue: "Счета"))
                                .font(AppTypography.h3)
                                .foregroundStyle(.primary)
                        }
                        
                        EmptyStateView(title: String(localized: "emptyState.noAccounts", defaultValue: "Нет счетов"), style: .compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardStyle(radius: AppRadius.pill)
                }
                .buttonStyle(.bounce)
                .screenPadding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(accountsViewModel.accounts) { account in
                            AccountCard(
                                account: account,
                                onTap: {
                                    selectedAccount = account
                                }
                            )
                            .id("\(account.id)-\(account.balance)")
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
                .scrollClipDisabled()
                .screenPadding()
            }
        }
    }
    private var subscriptionsCard: some View {
        SubscriptionsCardView(
            subscriptionsViewModel: subscriptionsViewModel,
            transactionsViewModel: viewModel
        )
    }
    
    private var categoriesSection: some View {
        QuickAddTransactionView(
            transactionsViewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel
        )
        .screenPadding()
    }
    
    private var analyticsCard: some View {
        let currency = viewModel.appSettings.baseCurrency

        if viewModel.allTransactions.isEmpty {
            return AnyView(
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack {
                        Text(String(localized: "analytics.history", defaultValue: "История"))
                            .font(AppTypography.h3)
                            .foregroundStyle(.primary)
                    }

                    EmptyStateView(title: String(localized: "emptyState.noTransactions", defaultValue: "Нет транзакций"), style: .compact)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCardStyle(radius: AppRadius.pill)
            )
        }

        // Compute summary directly - ViewModel has internal cache
        let summary = viewModel.summary(timeFilterManager: timeFilterManager)

        return AnyView(
            AnalyticsCard(
                summary: summary,
                currency: currency
            )
        )
    }
    
    
    private func analyzePDF(url: URL) async {
        
        await MainActor.run {
            viewModel.isLoading = true
            viewModel.errorMessage = nil
            ocrProgress = nil
            recognizedText = nil
        }
        
        do {
            // Извлекаем текст через PDFKit или OCR
            let ocrResult = try await PDFService.shared.extractText(from: url) { current, total in
                // Callback уже вызывается на MainActor в PDFService
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }
            
            
            // Проверяем, что текст не пустой
            let trimmedText = ocrResult.fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                await MainActor.run {
                    viewModel.errorMessage = String(localized: "error.pdfExtraction")
                    viewModel.isLoading = false
                    ocrProgress = nil
                }
                return
            }
            
            await MainActor.run {
                recognizedText = ocrResult.fullText
                structuredRows = ocrResult.structuredRows
                ocrProgress = nil
                viewModel.isLoading = false
                showingRecognizedText = true
            }
            
        } catch let error as PDFError {
            let errorMessage = error.localizedDescription
            await MainActor.run {
                viewModel.errorMessage = errorMessage
                viewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = String(format: String(localized: "error.pdfRecognitionFailed"), error.localizedDescription)
                viewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        }
    }
    
}


#Preview {
    ContentView()
        .environmentObject(TimeFilterManager())
}
