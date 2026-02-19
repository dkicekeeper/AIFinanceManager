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
    // MARK: - Environment (Modern @Observable with @Environment)
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

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
    // ✨ Phase 9: Use TransactionStore instead of SubscriptionsViewModel
    private var transactionStore: TransactionStore {
        coordinator.transactionStore
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
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
            // Phase 17: Only track time filter changes explicitly
            // Transaction data changes are tracked automatically via @Observable
            // on transactionStore.transactions (accessed through computed properties)
            .onChange(of: timeFilterManager.currentFilter) { _, _ in
                updateSummary()
            }
            .onChange(of: transactionStore.transactions.count) { _, _ in
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
                    },
                    balanceCoordinator: accountsViewModel.balanceCoordinator!
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
                transactionStore: transactionStore,
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
            accountsViewModel: accountsViewModel,
            transactionStore: coordinator.transactionStore
        )
        .screenPadding()
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            MessageBanner.error(error)
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
        .environment(timeFilterManager)
    }

    private var subscriptionsDestination: some View {
        SubscriptionsListView(
            transactionStore: transactionStore,
            transactionsViewModel: viewModel
        )
        .environment(timeFilterManager)
    }

    private var insightsDestination: some View {
        InsightsView(insightsViewModel: coordinator.insightsViewModel)
            .environment(timeFilterManager)
    }

    private var settingsDestination: some View {
        SettingsView(
            settingsViewModel: coordinator.settingsViewModel,
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            transactionStore: transactionStore,
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
                Text(String(localized: "progress.loadingData", defaultValue: "Loading data..."))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
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
                HStack(spacing: AppSpacing.md) {
                    insightsButton
                    settingsButton
                }
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
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(String(localized: "accessibility.calendar"))
        .accessibilityHint(String(localized: "accessibility.calendarHint"))
    }

    private var insightsButton: some View {
        NavigationLink(destination: insightsDestination) {
            Image(systemName: "chart.bar.xaxis")
        }
        .accessibilityLabel(String(localized: "insights.title"))
    }

    private var settingsButton: some View {
        NavigationLink(destination: settingsDestination) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel(String(localized: "accessibility.settings"))
        .accessibilityHint(String(localized: "accessibility.settingsHint"))
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
        NavigationStack {
            DepositDetailView(
                depositsViewModel: coordinator.depositsViewModel,
                transactionsViewModel: viewModel,
                balanceCoordinator: accountsViewModel.balanceCoordinator!,
                accountId: account.id
            )
            .environment(timeFilterManager)
        }
    }

    private func accountActionSheet(for account: Account) -> some View {
        AccountActionView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            account: account
        )
        .environment(timeFilterManager)
    }

    private var timeFilterSheet: some View {
        TimeFilterView(filterManager: timeFilterManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        Task {
            await accountsViewModel.addAccount(
                name: account.name,
                initialBalance: account.initialBalance ?? 0,
                currency: account.currency,
                iconSource: account.iconSource
            )
            viewModel.syncAccountsFrom(accountsViewModel)
            showingAddAccount = false
        }
    }

    // MARK: - Observable Pattern
    // With @Observable, SwiftUI automatically tracks dependencies
    // We use onChange modifiers above to trigger updates when specific properties change
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(TimeFilterManager())
        .environment(AppCoordinator())
}
