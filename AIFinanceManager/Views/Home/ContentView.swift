//
//  ContentView.swift
//  AIFinanceManager
//
//  Home screen - main entry point of the app
//  Refactored: 2026-02-01 - Full rebuild with SRP, optimized state management, and component extraction
//

import SwiftUI
import Combine

// MARK: - ContentView (Home Screen)

/// Main home screen displaying accounts, analytics, subscriptions, and quick actions
/// Single responsibility: Home screen UI orchestration
struct ContentView: View {
    // MARK: - Environment
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var timeFilterManager: TimeFilterManager

    // MARK: - State
    @State private var isInitializing = true
    @State private var selectedAccount: Account?
    @State private var showingTimeFilter = false
    @State private var showingAddAccount = false
    @State private var wallpaperImage: UIImage? = nil
    @State private var cachedSummary: Summary? = nil
    @State private var wallpaperLoadingTask: Task<Void, Never>? = nil

    // MARK: - Computed ViewModels (from coordinator)
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

    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                mainContent
                loadingOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .background { wallpaperBackground }
            .toolbar { toolbarContent }
            .sheet(item: $selectedAccount) { accountSheet(for: $0) }
            .sheet(isPresented: $showingTimeFilter) { timeFilterSheet }
            .sheet(isPresented: $showingAddAccount) { addAccountSheet }
            .task { await initializeIfNeeded() }
            .onAppear { setupOnAppear() }
            .onChange(of: viewModel.appSettings.wallpaperImageName) { _, _ in
                loadWallpaperOnce()
            }
            .onReceive(summaryUpdatePublisher) { _ in
                updateSummary()
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                accountsSection
                historyNavigationLink
                subscriptionsNavigationLink
                categoriesSection
                errorSection
            }
            .padding(.vertical, AppSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
        .opacity(isInitializing ? 0 : 1)
    }

    // MARK: - Sections

    private var accountsSection: some View {
        Group {
            if accountsViewModel.accounts.isEmpty {
                EmptyAccountsPrompt(onAddAccount: {
                    showingAddAccount = true
                })
            } else {
                AccountsCarousel(
                    accounts: accountsViewModel.accounts,
                    onAccountTap: { account in
                        selectedAccount = account
                    }
                )
            }
        }
    }

    private var historyNavigationLink: some View {
        NavigationLink(destination: historyDestination) {
            TransactionsSummaryCard(
                summary: cachedSummary,
                currency: viewModel.appSettings.baseCurrency,
                isEmpty: viewModel.allTransactions.isEmpty
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var subscriptionsNavigationLink: some View {
        NavigationLink(destination: subscriptionsDestination) {
            SubscriptionsCardView(
                subscriptionsViewModel: subscriptionsViewModel,
                transactionsViewModel: viewModel
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var categoriesSection: some View {
        QuickAddTransactionView(
            transactionsViewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel
        )
        .screenPadding()
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            ErrorMessageView(message: error)
                .screenPadding()
        }
    }

    private var bottomActions: some View {
        HStack(spacing: AppSpacing.xl) {
            VoiceInputCoordinator(
                transactionsViewModel: viewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel
            )

            PDFImportCoordinator(
                transactionsViewModel: viewModel,
                categoriesViewModel: categoriesViewModel
            )
        }
        .screenPadding()
        .padding(.bottom, AppSpacing.xl)
    }

    // MARK: - Destinations

    private var historyDestination: some View {
        HistoryView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            initialCategory: nil
        )
        .environmentObject(timeFilterManager)
    }

    private var subscriptionsDestination: some View {
        SubscriptionsListView(
            subscriptionsViewModel: subscriptionsViewModel,
            transactionsViewModel: viewModel
        )
        .environmentObject(timeFilterManager)
    }

    private var settingsDestination: some View {
        SettingsView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            subscriptionsViewModel: subscriptionsViewModel,
            depositsViewModel: coordinator.depositsViewModel
        )
    }

    // MARK: - Overlays & Backgrounds

    @ViewBuilder
    private var loadingOverlay: some View {
        if isInitializing {
            VStack(spacing: AppSpacing.lg) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(String(localized: LocalizationKeys.Progress.loadingData))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let wallpaperImage = wallpaperImage {
            Image(uiImage: wallpaperImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all, edges: .all)
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                timeFilterButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                settingsButton
            }
        }
    }

    private var timeFilterButton: some View {
        Button(action: {
            HapticManager.light()
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
        .accessibilityLabel(String(localized: LocalizationKeys.Accessibility.calendar))
        .accessibilityHint(String(localized: LocalizationKeys.Accessibility.calendarHint))
    }

    private var settingsButton: some View {
        NavigationLink(destination: settingsDestination) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel(String(localized: LocalizationKeys.Accessibility.settings))
        .accessibilityHint(String(localized: LocalizationKeys.Accessibility.settingsHint))
    }

    // MARK: - Sheets

    @ViewBuilder
    private func accountSheet(for account: Account) -> some View {
        if account.isDeposit {
            depositDetailSheet(for: account)
        } else {
            accountActionSheet(for: account)
        }
    }

    private func depositDetailSheet(for account: Account) -> some View {
        NavigationView {
            DepositDetailView(
                depositsViewModel: coordinator.depositsViewModel,
                transactionsViewModel: viewModel,
                accountId: account.id
            )
            .environmentObject(timeFilterManager)
        }
    }

    private func accountActionSheet(for account: Account) -> some View {
        AccountActionView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            account: account
        )
        .environmentObject(timeFilterManager)
    }

    private var timeFilterSheet: some View {
        TimeFilterView(filterManager: timeFilterManager)
    }

    private var addAccountSheet: some View {
        AccountEditView(
            accountsViewModel: accountsViewModel,
            transactionsViewModel: viewModel,
            account: nil,
            onSave: handleAccountSave,
            onCancel: {
                showingAddAccount = false
            }
        )
    }

    // MARK: - Lifecycle Methods

    private func initializeIfNeeded() async {
        guard isInitializing else { return }
        await coordinator.initialize()
        withAnimation {
            isInitializing = false
        }
    }

    private func setupOnAppear() {
        PerformanceProfiler.start("ContentView.onAppear")
        loadWallpaperOnce()
        updateSummary()
        PerformanceProfiler.end("ContentView.onAppear")
    }

    // MARK: - State Updates

    private func updateSummary() {
        PerformanceProfiler.start("ContentView.updateSummary")
        cachedSummary = viewModel.summary(timeFilterManager: timeFilterManager)
        PerformanceProfiler.end("ContentView.updateSummary")
    }

    private func loadWallpaperOnce() {
        guard wallpaperLoadingTask == nil else { return }

        wallpaperLoadingTask = Task.detached(priority: .userInitiated) {
            guard let wallpaperName = await MainActor.run(body: {
                viewModel.appSettings.wallpaperImageName
            }) else {
                await MainActor.run {
                    wallpaperImage = nil
                }
                return
            }

            let documentsPath = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            let fileURL = documentsPath.appendingPathComponent(wallpaperName)

            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let image = UIImage(contentsOfFile: fileURL.path) else {
                await MainActor.run {
                    wallpaperImage = nil
                }
                return
            }

            await MainActor.run {
                wallpaperImage = image
            }
        }
    }

    // MARK: - Event Handlers

    private func handleAccountSave(_ account: Account) {
        HapticManager.success()
        accountsViewModel.addAccount(
            name: account.name,
            balance: account.balance,
            currency: account.currency,
            bankLogo: account.bankLogo
        )
        viewModel.syncAccountsFrom(accountsViewModel)
        showingAddAccount = false
    }

    // MARK: - Combine Publishers

    /// Combines time filter and transactions changes with debounce to prevent duplicate updates
    private var summaryUpdatePublisher: AnyPublisher<Void, Never> {
        Publishers.Merge(
            timeFilterManager.$currentFilter.map { _ in () },
            viewModel.$allTransactions.map { _ in () }
        )
        .debounce(for: 0.1, scheduler: RunLoop.main)
        .eraseToAnyPublisher()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(TimeFilterManager())
        .environmentObject(AppCoordinator())
}
