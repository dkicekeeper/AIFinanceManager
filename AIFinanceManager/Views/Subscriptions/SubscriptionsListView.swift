//
//  SubscriptionsListView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Namespace private var subscriptionNamespace
    private enum SubscriptionSheetItem: Identifiable {
        case new
        case edit(RecurringSeries)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let sub): return sub.id
            }
        }
    }
    @State private var sheetItem: SubscriptionSheetItem?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !transactionStore.subscriptions.isEmpty {
                    SubscriptionCalendarView(
                        subscriptions: transactionStore.subscriptions,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency
                    )
                    .screenPadding()
                }

                if transactionStore.subscriptions.isEmpty {
                    emptyState
                        .screenPadding()
                } else {
                    subscriptionsList
                        .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "subscriptions.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: RecurringSeries.self) { subscription in
            SubscriptionDetailView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                subscription: subscription
            )
            .environment(timeFilterManager)
            .navigationTransition(.zoom(sourceID: subscription.id, in: subscriptionNamespace))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetItem = .new
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheetItem) { item in
            switch item {
            case .new:
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    subscription: nil
                )
            case .edit(let subscription):
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    subscription: subscription
                )
            }
        }
    }
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "creditcard",
            title: String(localized: "subscriptions.empty"),
            description: String(localized: "subscriptions.emptyDescription"),
            actionTitle: String(localized: "subscriptions.addSubscription"),
            action: {
                sheetItem = .new
            }
        )
    }
    
    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(transactionStore.subscriptions) { subscription in
                let nextChargeDate = transactionStore.nextChargeDate(for: subscription.id)

                NavigationLink(value: subscription) {
                    SubscriptionCard(
                        subscription: subscription,
                        nextChargeDate: nextChargeDate
                    )
                    .matchedTransitionSource(id: subscription.id, in: subscriptionNamespace)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Previews

#Preview("Subscriptions List - Empty") {
    let coordinator = AppCoordinator()
    return NavigationStack {
        SubscriptionsListView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Subscriptions List - With Data") {
    let coordinator = AppCoordinator()
    let transactionStore = coordinator.transactionStore
    let transactionsViewModel = coordinator.transactionsViewModel

    // Add sample subscriptions for preview
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())

    let sampleSubscriptions = [
        RecurringSeries(
            id: "preview-1",
            amount: Decimal(9.99),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            accountId: "preview-account",
            frequency: .monthly,
            startDate: today,
            kind: .subscription,
            iconSource: .brandService("Netflix"),
            status: .active
        ),
        RecurringSeries(
            id: "preview-2",
            amount: Decimal(15.00),
            currency: "USD",
            category: "Entertainment",
            description: "Spotify Premium",
            accountId: "preview-account",
            frequency: .monthly,
            startDate: today,
            kind: .subscription,
            iconSource: .brandService("Spotify"),
            status: .active
        ),
        RecurringSeries(
            id: "preview-3",
            amount: Decimal(99.00),
            currency: "USD",
            category: "Software",
            description: "Adobe Creative Cloud",
            accountId: "preview-account",
            frequency: .monthly,
            startDate: today,
            kind: .subscription,
            iconSource: .brandService("Adobe"),
            status: .paused
        )
    ]

    // Note: In real preview, subscriptions would be loaded from repository
    // For now, preview shows empty state or you can add test data via repository

    NavigationStack {
        SubscriptionsListView(
            transactionStore: transactionStore,
            transactionsViewModel: transactionsViewModel
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Subscription Card") {
    let coordinator = AppCoordinator()
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())

    let sampleSubscription = RecurringSeries(
        id: "preview-card",
        amount: Decimal(9.99),
        currency: "USD",
        category: "Entertainment",
        description: "Netflix",
        accountId: "preview-account",
        frequency: .monthly,
        startDate: today,
        kind: .subscription,
        iconSource: .brandService("Netflix"),
        status: .active
    )

    SubscriptionCard(
        subscription: sampleSubscription,
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
