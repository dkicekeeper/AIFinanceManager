//
//  SubscriptionDetailView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionDetailView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    let subscription: RecurringSeries
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) var dismiss

    // ✨ Phase 9: Use TransactionStore.getPlannedTransactions()
    private var subscriptionTransactions: [Transaction] {
        // Get all existing transactions for this subscription from store
        let existingTransactions = transactionStore.transactions.filter {
            $0.recurringSeriesId == subscription.id
        }

        // Get future planned transactions (next 6 months)
        let plannedTransactions = transactionStore.getPlannedTransactions(for: subscription.id, horizon: 6)

        // Combine and sort by date (ascending - nearest first, furthest last)
        let allTransactions = (existingTransactions + plannedTransactions)
            .sorted { $0.date < $1.date } // Nearest first (ascending order)

        return allTransactions
    }

    private var nextChargeDate: Date? {
        transactionStore.nextChargeDate(for: subscription.id)
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
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                subscription: subscription,
                onSave: { updatedSubscription in
                    Task {
                        try await transactionStore.updateSeries(updatedSubscription)
                        showingEditView = false
                    }
                },
                onCancel: {
                    showingEditView = false
                }
            )
        }
        .alert(String(localized: "subscriptions.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}

            Button(String(localized: "subscriptions.deleteOnlySubscription"), role: .destructive) {
                Task {
                    try await transactionStore.deleteSeries(id: subscription.id, deleteTransactions: false)
                    dismiss()
                }
            }

            Button(String(localized: "subscriptions.deleteSubscriptionAndTransactions"), role: .destructive) {
                Task {
                    try await transactionStore.deleteSeries(id: subscription.id, deleteTransactions: true)
                    dismiss()
                }
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
                    iconSource: subscription.iconSource,
                    size: AppIconSize.xxxl
                )
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(subscription.description)
                        .font(AppTypography.h3)

                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                        currency: subscription.currency,
                        fontSize: AppTypography.h4,
                        color: .secondary
                    )
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
                    Task {
                        try await transactionStore.pauseSubscription(id: subscription.id)
                    }
                } label: {
                    Label(String(localized: "subscriptions.pause"), systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButton()
            } else if subscription.subscriptionStatus == .paused {
                Button {
                    Task {
                        try await transactionStore.resumeSubscription(id: subscription.id)
                    }
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
    NavigationStack {
        SubscriptionDetailView(
            transactionStore: coordinator.transactionStore,
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
