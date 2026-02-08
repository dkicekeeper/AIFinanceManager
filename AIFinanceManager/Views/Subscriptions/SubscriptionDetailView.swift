//
//  SubscriptionDetailView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionDetailView: View {
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    let subscription: RecurringSeries
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) var dismiss

    // REFACTORED 2026-02-02: Removed 110 LOC of duplicated logic
    // Now delegates to SubscriptionsViewModel.getPlannedTransactions()
    private var subscriptionTransactions: [Transaction] {
        // Get all planned transactions (past + future)
        let plannedTransactions = subscriptionsViewModel.getPlannedTransactions(for: subscription.id, horizonMonths: 3)

        // Apply time filter if needed
        let dateRange = timeFilterManager.currentFilter.dateRange()
        let dateFormatter = DateFormatters.dateFormatter

        return plannedTransactions.filter { transaction in
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= dateRange.start && transactionDate < dateRange.end
        }
    }
    
    private var nextChargeDate: Date? {
        subscriptionsViewModel.nextChargeDate(for: subscription.id)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Info card
                subscriptionInfoCard
                    .screenPadding()
                
                // Actions
                actionsSection
                    .screenPadding()
                
                // Transactions history
                if !subscriptionTransactions.isEmpty {
                    transactionsSection
                        .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(subscription.description)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEditView = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            SubscriptionEditView(
                subscriptionsViewModel: subscriptionsViewModel,
                transactionsViewModel: transactionsViewModel,
                subscription: subscription,
                onSave: { updatedSubscription in
                    subscriptionsViewModel.updateSubscription(updatedSubscription)
                    // ✅ FIX 2026-02-08: Transaction regeneration is handled automatically via .recurringSeriesUpdated notification
                    // No need to call generateRecurringTransactions() manually
                    showingEditView = false
                },
                onCancel: {
                    showingEditView = false
                }
            )
        }
        .alert(String(localized: "subscriptions.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}

            Button(String(localized: "subscriptions.deleteOnlySubscription"), role: .destructive) {
                subscriptionsViewModel.deleteRecurringSeries(subscription.id, deleteTransactions: false)
                transactionsViewModel.deleteRecurringSeries(subscription.id, deleteTransactions: false)
                // Phase 8: saveToStorage removed - persistence automatic via TransactionStore
                dismiss()
            }

            Button(String(localized: "subscriptions.deleteSubscriptionAndTransactions"), role: .destructive) {
                subscriptionsViewModel.deleteRecurringSeries(subscription.id, deleteTransactions: true)
                transactionsViewModel.allTransactions.removeAll { $0.recurringSeriesId == subscription.id }
                transactionsViewModel.recalculateAccountBalances()
                // Phase 8: saveToStorage removed - persistence automatic via TransactionStore
                dismiss()
            }
        } message: {
            Text(String(localized: "subscriptions.deleteConfirmMessage"))
        }
    }
    
    private var subscriptionInfoCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                // REFACTORED 2026-02-02: Use BrandLogoDisplayView to eliminate duplication
                BrandLogoDisplayView(
                    brandLogo: subscription.brandLogo,
                    brandId: subscription.brandId,
                    brandName: subscription.description,
                    size: AppIconSize.xxxl
                )
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(subscription.description)
                        .font(AppTypography.h3)
                    
                    Text(Formatting.formatCurrency(
                        NSDecimalNumber(decimal: subscription.amount).doubleValue,
                        currency: subscription.currency
                    ))
                    .font(AppTypography.h4)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                InfoRow(label: String(localized: "subscriptions.category"), value: subscription.category)
                InfoRow(label: String(localized: "subscriptions.frequency"), value: subscription.frequency.displayName)

                if let nextDate = nextChargeDate {
                    InfoRow(label: String(localized: "subscriptions.nextCharge"), value: formatDate(nextDate))
                }

                if let accountId = subscription.accountId,
                   let account = transactionsViewModel.accounts.first(where: { $0.id == accountId }) {
                    InfoRow(label: String(localized: "subscriptions.account"), value: account.name)
                }

                InfoRow(label: String(localized: "subscriptions.status"), value: statusText)
            }
        }
        .cardStyle()
    }
    
    private var statusText: String {
        switch subscription.subscriptionStatus {
        case .active:
            return String(localized: "subscriptions.status.active")
        case .paused:
            return String(localized: "subscriptions.status.paused")
        case .archived:
            return String(localized: "subscriptions.status.archived")
        case .none:
            return String(localized: "subscriptions.status.unknown")
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            if subscription.subscriptionStatus == .active {
                Button {
                    subscriptionsViewModel.pauseSubscription(subscription.id)
                } label: {
                    Label(String(localized: "subscriptions.pause"), systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else if subscription.subscriptionStatus == .paused {
                Button {
                    subscriptionsViewModel.resumeSubscription(subscription.id)
                    transactionsViewModel.generateRecurringTransactions()
                } label: {
                    Label(String(localized: "subscriptions.resume"), systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "subscriptions.delete"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .destructiveButton()
        }
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "subscriptions.transactionHistory"))
                .font(AppTypography.h4)
            
            VStack(spacing: AppSpacing.sm) {
                ForEach(subscriptionTransactions) { transaction in
                    DepositTransactionRow(transaction: transaction, currency: transaction.currency, isPlanned: transaction.id.hasPrefix("planned-"))
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }
}



#Preview {
    let coordinator = AppCoordinator()
    NavigationView {
        SubscriptionDetailView(
            subscriptionsViewModel: coordinator.subscriptionsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            subscription: RecurringSeries(
                amount: 9.99,
                currency: "USD",
                category: "Entertainment",
                description: "Netflix",
                frequency: .monthly,
                startDate: "2024-01-01",
                kind: .subscription
            )
        )
    }
}
