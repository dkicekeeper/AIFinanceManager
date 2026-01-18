//
//  SubscriptionsListView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var showingEditView = false
    @State private var editingSubscription: RecurringSeries?
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !subscriptionsViewModel.subscriptions.isEmpty {
                    SubscriptionCalendarView(subscriptions: subscriptionsViewModel.subscriptions)
                        .screenPadding()
                }
                
                if subscriptionsViewModel.subscriptions.isEmpty {
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
                        subscriptionsViewModel: subscriptionsViewModel,
                        transactionsViewModel: transactionsViewModel,
                        subscription: subscription,
                        onSave: { updatedSubscription in
                            subscriptionsViewModel.updateSubscription(updatedSubscription)
                            // Regenerate recurring transactions
                            transactionsViewModel.generateRecurringTransactions()
                            showingEditView = false
                        },
                        onCancel: {
                            showingEditView = false
                        }
                    )
                } else {
                    SubscriptionEditView(
                        subscriptionsViewModel: subscriptionsViewModel,
                        transactionsViewModel: transactionsViewModel,
                        subscription: nil,
                        onSave: { newSubscription in
                            _ = subscriptionsViewModel.createSubscription(
                                amount: newSubscription.amount,
                                currency: newSubscription.currency,
                                category: newSubscription.category,
                                subcategory: newSubscription.subcategory,
                                description: newSubscription.description,
                                accountId: newSubscription.accountId,
                                frequency: newSubscription.frequency,
                                startDate: newSubscription.startDate,
                                brandLogo: newSubscription.brandLogo,
                                brandId: newSubscription.brandId,
                                reminderOffsets: newSubscription.reminderOffsets
                            )
                            // Regenerate recurring transactions
                            transactionsViewModel.generateRecurringTransactions()
                            showingEditView = false
                        },
                        onCancel: {
                            showingEditView = false
                        }
                    )
                }
            }
    }
    
    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "creditcard")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text(String(localized: "subscriptions.empty"))
                .font(AppTypography.h3)

            Text(String(localized: "subscriptions.emptyDescription"))
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                editingSubscription = nil
                showingEditView = true
            } label: {
                Text(String(localized: "subscriptions.addSubscription"))
            }
            .primaryButton()
            .padding(.top, AppSpacing.md)
        }
        .padding(AppSpacing.xxl)
    }
    
    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(subscriptionsViewModel.subscriptions) { subscription in
                NavigationLink(destination: SubscriptionDetailView(
                    subscriptionsViewModel: subscriptionsViewModel,
                    transactionsViewModel: transactionsViewModel,
                    subscription: subscription
                )
                    .environmentObject(timeFilterManager)) {
                    SubscriptionCard(subscription: subscription, subscriptionsViewModel: subscriptionsViewModel, transactionsViewModel: transactionsViewModel)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsListView(
        subscriptionsViewModel: coordinator.subscriptionsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
}
