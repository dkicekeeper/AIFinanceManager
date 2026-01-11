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

struct SubscriptionCard: View {
    let subscription: RecurringSeries
    @ObservedObject var viewModel: TransactionsViewModel
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Logo - показываем сохраненный brandLogo, иконку или fallback
            if let brandLogo = subscription.brandLogo {
                brandLogo.image(size: AppIconSize.xxl)
            } else if let brandId = subscription.brandId, !brandId.isEmpty {
                // Проверяем, является ли brandId иконкой (начинается с "sf:" или "icon:")
                if brandId.hasPrefix("sf:") {
                    let iconName = String(brandId.dropFirst(3))
                    Image(systemName: iconName)
                        .font(.system(size: AppIconSize.xxl * 0.6))
                        .foregroundColor(.secondary)
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: AppIconSize.xxl * 0.2))
                } else if brandId.hasPrefix("icon:") {
                    let iconName = String(brandId.dropFirst(5))
                    Image(systemName: iconName)
                        .font(.system(size: AppIconSize.xxl * 0.6))
                        .foregroundColor(.secondary)
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: AppIconSize.xxl * 0.2))
                } else {
                    // Если есть brandId (название бренда), показываем через BrandLogoView
                    BrandLogoView(brandName: brandId, size: AppIconSize.xxl)
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                }
            } else {
                // Fallback
                Image(systemName: "creditcard")
                    .font(.system(size: AppIconSize.xxl * 0.6))
                    .foregroundColor(.secondary)
                    .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: AppIconSize.xxl * 0.2))
            }
            
            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subscription.description)
                    .font(AppTypography.bodyLarge.weight(.semibold))
                
                Text(Formatting.formatCurrency(
                    NSDecimalNumber(decimal: subscription.amount).doubleValue,
                    currency: subscription.currency
                ))
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                
                if let nextChargeDate = viewModel.nextChargeDate(for: subscription.id) {
                    Text("Следующее списание: \(formatDate(nextChargeDate))")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            statusIndicator
        }
        .cardStyle()
    }
    
    private var statusIndicator: some View {
        Group {
            switch subscription.subscriptionStatus {
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
            case .archived:
                Image(systemName: "archive.circle.fill")
                    .foregroundColor(.gray)
            case .none:
                EmptyView()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatters.displayDateFormatter
        return formatter.string(from: date)
    }
}

#Preview {
    SubscriptionsListView(viewModel: TransactionsViewModel())
}
