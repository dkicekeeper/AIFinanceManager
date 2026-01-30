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
    
    private var subscriptionTransactions: [Transaction] {
        // Получаем существующие транзакции
        let existingTransactions = transactionsViewModel.allTransactions.filter { $0.recurringSeriesId == subscription.id }
            .sorted { $0.date > $1.date }
        
        // Получаем диапазон дат из фильтра
        let dateRange = timeFilterManager.currentFilter.dateRange()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatters.dateFormatter
        
        // Генерируем планируемые транзакции в рамках фильтра (как в "в планах")
        var allTransactions: [Transaction] = existingTransactions
        
        // Если фильтр включает будущие даты, генерируем планируемые транзакции
        if dateRange.end > today && subscription.subscriptionStatus == .active {
            guard let seriesStartDate = dateFormatter.date(from: subscription.startDate) else {
                return existingTransactions.sorted { $0.date > $1.date }
            }
            
            // Определяем начало планирования
            var firstRecurringDate: Date
            if seriesStartDate <= today {
                // Серия уже началась - первая будущая транзакция будет на следующей дате по частоте
                guard let nextDate = {
                    switch subscription.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: today)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: today)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: today)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: today)
                    }
                }() else {
                    return existingTransactions.sorted { $0.date > $1.date }
                }
                firstRecurringDate = nextDate
            } else {
                // Серия начинается в будущем - первая транзакция на startDate
                firstRecurringDate = seriesStartDate
            }
            
            // Генерируем транзакции в рамках фильтра
            let planningEnd = min(dateRange.end, calendar.date(byAdding: .year, value: 2, to: today) ?? dateRange.end)
            var currentDate = firstRecurringDate
            
            while currentDate < planningEnd {
                let dateString = dateFormatter.string(from: currentDate)
                
                // Проверяем, не существует ли уже транзакция на эту дату
                let existingOnDate = existingTransactions.first { $0.date == dateString }
                if existingOnDate == nil {
                    // Создаем виртуальную транзакцию для отображения
                    let plannedTransaction = Transaction(
                        id: "planned-\(subscription.id)-\(dateString)",
                        date: dateString,
                        description: subscription.description,
                        amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                        currency: subscription.currency,
                        convertedAmount: nil,
                        type: .expense,
                        category: subscription.category,
                        subcategory: subscription.subcategory,
                        accountId: subscription.accountId,
                        targetAccountId: nil,
                        recurringSeriesId: subscription.id,
                        recurringOccurrenceId: nil,
                        createdAt: currentDate.timeIntervalSince1970
                    )
                    allTransactions.append(plannedTransaction)
                }
                
                // Переходим к следующей дате по частоте
                guard let nextDate = {
                    switch subscription.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: currentDate)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: currentDate)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: currentDate)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: currentDate)
                    }
                }() else {
                    break
                }
                currentDate = nextDate
            }
        }
        
        // Фильтруем транзакции по диапазону дат и сортируем: ближайшие сверху, дальние снизу
        return allTransactions
            .filter { transaction in
                guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return transactionDate >= dateRange.start && transactionDate < dateRange.end
            }
            .sorted { transaction1, transaction2 in
                guard let date1 = dateFormatter.date(from: transaction1.date),
                      let date2 = dateFormatter.date(from: transaction2.date) else {
                    return transaction1.date < transaction2.date // Fallback: строковое сравнение
                }
                return date1 < date2 // Ближайшие сверху
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
                    transactionsViewModel.generateRecurringTransactions()
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
                transactionsViewModel.saveToStorage()
                dismiss()
            }

            Button(String(localized: "subscriptions.deleteSubscriptionAndTransactions"), role: .destructive) {
                subscriptionsViewModel.deleteRecurringSeries(subscription.id, deleteTransactions: true)
                transactionsViewModel.allTransactions.removeAll { $0.recurringSeriesId == subscription.id }
                transactionsViewModel.recalculateAccountBalances()
                transactionsViewModel.saveToStorage()
                dismiss()
            }
        } message: {
            Text(String(localized: "subscriptions.deleteConfirmMessage"))
        }
    }
    
    private var subscriptionInfoCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                // Logo - показываем сохраненный brandLogo, иконку или fallback
                if let brandLogo = subscription.brandLogo {
                    brandLogo.image(size: AppIconSize.xxxl)
                } else if let brandId = subscription.brandId, !brandId.isEmpty {
                    // Проверяем, является ли brandId иконкой (начинается с "sf:" или "icon:")
                    if brandId.hasPrefix("sf:") {
                        let iconName = String(brandId.dropFirst(3))
                        Image(systemName: iconName)
                            .fallbackIconStyle(size: AppIconSize.xxxl)
                    } else if brandId.hasPrefix("icon:") {
                        let iconName = String(brandId.dropFirst(5))
                        Image(systemName: iconName)
                            .fallbackIconStyle(size: AppIconSize.xxxl)
                    } else {
                        // Если есть brandId (название бренда), показываем через BrandLogoView
                        BrandLogoView(brandName: brandId, size: AppIconSize.xxxl)
                            .frame(width: AppIconSize.xxxl, height: AppIconSize.xxxl)
                    }
                } else {
                    // Fallback
                    Image(systemName: "creditcard")
                        .fallbackIconStyle(size: AppIconSize.xxxl)
                }
                
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
