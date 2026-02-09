//
//  SubscriptionsListView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    @ObservedObject var transactionStore: TransactionStore
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var showingEditView = false
    @State private var editingSubscription: RecurringSeries?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !transactionStore.subscriptions.isEmpty {
                    SubscriptionCalendarView(subscriptions: transactionStore.subscriptions)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingSubscription = nil
                    showingEditView = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
            .sheet(isPresented: $showingEditView) {
                if let subscription = editingSubscription {
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
                } else {
                    SubscriptionEditView(
                        transactionStore: transactionStore,
                        transactionsViewModel: transactionsViewModel,
                        subscription: nil,
                        onSave: { newSubscription in
                            Task {
                                try await transactionStore.createSeries(newSubscription)
                                showingEditView = false
                            }
                        },
                        onCancel: {
                            showingEditView = false
                        }
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
                editingSubscription = nil
                showingEditView = true
            }
        )
    }
    
    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(transactionStore.subscriptions) { subscription in
                let nextChargeDate = transactionStore.nextChargeDate(for: subscription.id)

                NavigationLink(destination: SubscriptionDetailView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    subscription: subscription
                )
                    .environmentObject(timeFilterManager)) {
                    SubscriptionCard(
                        subscription: subscription,
                        nextChargeDate: nextChargeDate
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Previews

#Preview("Subscriptions List - Empty") {
    let coordinator = AppCoordinator()
    return NavigationView {
        SubscriptionsListView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel
        )
        .environmentObject(TimeFilterManager())
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
            brandId: "Netflix",
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
            brandId: "Spotify",
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
            brandId: "Adobe",
            status: .paused
        )
    ]

    // Note: In real preview, subscriptions would be loaded from repository
    // For now, preview shows empty state or you can add test data via repository

    NavigationView {
        SubscriptionsListView(
            transactionStore: transactionStore,
            transactionsViewModel: transactionsViewModel
        )
        .environmentObject(TimeFilterManager())
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
        brandId: "Netflix",
        status: .active
    )

    SubscriptionCard(
        subscription: sampleSubscription,
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
