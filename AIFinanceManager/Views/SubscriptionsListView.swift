//
//  SubscriptionsListView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var showingEditView = false
    @State private var editingSubscription: RecurringSeries?
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if viewModel.subscriptions.isEmpty {
                    emptyState
                        .screenPadding()
                } else {
                    subscriptionsList
                        .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("Подписки")
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
                        viewModel: viewModel,
                        subscription: subscription,
                        onSave: { updatedSubscription in
                            viewModel.updateSubscription(updatedSubscription)
                            showingEditView = false
                        },
                        onCancel: {
                            showingEditView = false
                        }
                    )
                } else {
                    SubscriptionEditView(
                        viewModel: viewModel,
                        subscription: nil,
                        onSave: { newSubscription in
                            _ = viewModel.createSubscription(
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
            
            Text("Нет подписок")
                .font(AppTypography.h3)
            
            Text("Добавьте подписку, чтобы отслеживать регулярные платежи")
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                editingSubscription = nil
                showingEditView = true
            } label: {
                Text("Добавить подписку")
            }
            .primaryButton()
            .padding(.top, AppSpacing.md)
        }
        .padding(AppSpacing.xxl)
    }
    
    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(viewModel.subscriptions) { subscription in
                NavigationLink(destination: SubscriptionDetailView(viewModel: viewModel, subscription: subscription)
                    .environmentObject(timeFilterManager)) {
                    SubscriptionCard(subscription: subscription, viewModel: viewModel)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    SubscriptionsListView(viewModel: TransactionsViewModel())
}
