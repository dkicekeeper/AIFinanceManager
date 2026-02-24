//
//  ContentView.swift
//  AIFinanceManager
//
//  Home screen - main entry point of the app
//  Refactored: 2026-02-01 - Full rebuild with SRP, optimized state management, and component extraction
//

import SwiftUI
import os
import QuartzCore

private let cvLogger = Logger(subsystem: "AIFinanceManager", category: "ContentView")

// MARK: - ContentView (Home Screen)

/// Main home screen displaying accounts, analytics, subscriptions, and quick actions
/// Single responsibility: Home screen UI orchestration
struct ContentView: View {
    // MARK: - Environment (Modern @Observable with @Environment)
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - State
    @State private var selectedAccount: Account?
    @State private var showingTimeFilter = false
    @State private var showingAddAccount = false
    @State private var wallpaperImage: UIImage? = nil
    @State private var cachedSummary: Summary? = nil
    @State private var wallpaperLoadingTask: Task<Void, Never>? = nil
    /// Guards setupOnAppear so the expensive updateSummary() runs only once on first
    /// appearance. Re-appearances (back-nav from History, Accounts, etc.) skip it because
    /// transactions.count onChange already keeps cachedSummary up-to-date.
    @State private var hasAppearedOnce = false

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
            mainContent
            .navigationBarTitleDisplayMode(.inline)
            .background { wallpaperBackground }
            .toolbar { toolbarContent }
            .sheet(item: $selectedAccount) { accountSheet(for: $0) }
            .sheet(isPresented: $showingTimeFilter) { timeFilterSheet }
            .sheet(isPresented: $showingAddAccount) { addAccountSheet }
            .task {
                await coordinator.initializeFastPath()
                await coordinator.initialize()
            }
            .onAppear { setupOnAppear() }
            .onChange(of: viewModel.appSettings.wallpaperImageName) { _, _ in
                loadWallpaperOnce()
            }
            // Phase 17: Only track time filter changes explicitly
            // Transaction data changes are tracked automatically via @Observable
            // on transactionStore.transactions (accessed through computed properties)
            .onChange(of: timeFilterManager.currentFilter) { oldFilter, newFilter in
                cvLogger.debug("🕐 [ContentView] timeFilter: .\(oldFilter.preset.rawValue) → .\(newFilter.preset.rawValue)")
                updateSummary()
            }
            .onChange(of: transactionStore.transactions.count) { oldCount, newCount in
                let t0 = CACurrentMediaTime()
                cvLogger.debug("🔢 [ContentView] transactions.count: \(oldCount)→\(newCount) — calling updateSummary()")
                updateSummary()
                cvLogger.debug("🔢 [ContentView] updateSummary() after count change: \(String(format: "%.0f", (CACurrentMediaTime()-t0)*1000))ms")
            }
            .onChange(of: coordinator.isFastPathDone) { _, isDone in
                cvLogger.debug("⚡️ [ContentView] isFastPathDone → \(isDone)")
            }
            .onChange(of: coordinator.isFullyInitialized) { _, isInit in
                cvLogger.debug("✅ [ContentView] isFullyInitialized → \(isInit) — skeleton removal triggered")
                // Do NOT call updateSummary() here.
                // onChange(of: transactionStore.transactions.count) fires milliseconds before
                // this handler and already ran the 275ms summary calculation.
                // Calling it again here would double-block the main thread for no benefit.
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                accountsSection
                    .skeletonLoading(isLoading: !coordinator.isFastPathDone) {
                        AccountsCarouselSkeleton()
                    }
                historyNavigationLink
                    .skeletonLoading(isLoading: !coordinator.isFullyInitialized) {
                        // .screenPadding() mirrors the one inside historyNavigationLink —
                        // SkeletonLoadingModifier shows skeleton XOR real content, never both.
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                subscriptionsNavigationLink
                    .skeletonLoading(isLoading: !coordinator.isFullyInitialized) {
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                categoriesSection
                    .skeletonLoading(isLoading: !coordinator.isFastPathDone) {
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                errorSection
            }
            .padding(.vertical, AppSpacing.md)
        }
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

    // MARK: - Destinations

    private var historyDestination: some View {
        HistoryView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            paginationController: coordinator.transactionPaginationController,
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

    // MARK: - Overlays & Backgrounds

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
        ToolbarItem(placement: .navigationBarLeading) {
            timeFilterButton
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

    private func setupOnAppear() {
        let t0 = CACurrentMediaTime()
        cvLogger.debug("🏠 [ContentView] onAppear START — isFastPathDone:\(self.coordinator.isFastPathDone) isFullyInitialized:\(self.coordinator.isFullyInitialized) sections:\(self.coordinator.transactionPaginationController.sections.count) firstTime:\(!self.hasAppearedOnce)")
        PerformanceProfiler.start("ContentView.onAppear")
        loadWallpaperOnce()

        // Only run updateSummary() on first appearance. On back-navigation the
        // cachedSummary is already current — transactions.count onChange keeps it fresh.
        if !hasAppearedOnce {
            hasAppearedOnce = true
            updateSummary()
        }

        cvLogger.debug("🏠 [ContentView] onAppear DONE in \(String(format: "%.0f", (CACurrentMediaTime()-t0)*1000))ms")
        PerformanceProfiler.end("ContentView.onAppear")
    }

    // MARK: - State Updates

    private func updateSummary() {
        let t0 = CACurrentMediaTime()
        PerformanceProfiler.start("ContentView.updateSummary")
        cachedSummary = viewModel.summary(timeFilterManager: timeFilterManager)
        let dt = CACurrentMediaTime() - t0
        if dt > 0.005 { // log if > 5ms
            cvLogger.debug("📊 [ContentView] updateSummary() \(String(format: "%.0f", dt*1000))ms — allTx:\(self.viewModel.allTransactions.count)")
        }
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

// MARK: - Skeleton Components

/// Accounts carousel skeleton: 3 cards (200×120) in horizontal scroll.
private struct AccountsCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(height: 120, cornerRadius: AppRadius.md)
                        .frame(width: 200)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityHidden(true)
    }
}

/// Generic section card skeleton: icon circle + 2 text lines.
/// Used for TransactionsSummaryCard, SubscriptionsCard, and QuickAdd skeletons.
private struct SectionCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            SkeletonView(width: 36, height: 36, cornerRadius: AppRadius.circle)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 140, height: 14)
                SkeletonView(width: 100, height: 12, cornerRadius: AppRadius.xs)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(TimeFilterManager())
        .environment(AppCoordinator())
}
