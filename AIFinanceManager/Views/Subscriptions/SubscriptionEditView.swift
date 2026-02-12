//
//  SubscriptionEditView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionEditView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let subscription: RecurringSeries?
    let onSave: (RecurringSeries) -> Void
    let onCancel: () -> Void

    @State private var description: String = ""
    @State private var amountText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedCategory: String? = nil
    @State private var selectedAccountId: String? = nil
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var selectedIconSource: IconSource? = nil
    @State private var selectedReminderOffsets: Set<Int> = []
    @State private var showingIconPicker = false
    @State private var validationError: String? = nil
    @FocusState private var isDescriptionFocused: Bool

    private let reminderOptions: [Int] = [1, 3, 7, 30]
    
    private var availableCategories: [String] {
        var categories: Set<String> = []
        for customCategory in transactionsViewModel.customCategories where customCategory.type == .expense {
            categories.insert(customCategory.name)
        }
        for tx in transactionsViewModel.allTransactions where tx.type == .expense {
            if !tx.category.isEmpty && tx.category != "Uncategorized" {
                categories.insert(tx.category)
            }
        }
        if categories.isEmpty {
            categories.insert("Uncategorized")
        }
        return Array(categories).sortedByCustomOrder(customCategories: transactionsViewModel.customCategories, type: .expense)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // 1. Amount Input
                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $currency,
                        errorMessage: validationError,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                        onAmountChange: { _ in
                            validationError = nil
                        }
                    )

                    // 2. Account Selector
                    AccountSelectorView(
                        accounts: transactionsViewModel.accounts,
                        selectedAccountId: $selectedAccountId,
                        emptyStateMessage: transactionsViewModel.accounts.isEmpty ? "Нет доступных счетов" : nil,
                        warningMessage: selectedAccountId == nil ? "Выберите счёт" : nil,
                        balanceCoordinator: transactionsViewModel.balanceCoordinator!
                    )

                    // 3. Category Selector
                    CategorySelectorView(
                        categories: availableCategories,
                        type: .expense,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $selectedCategory,
                        warningMessage: selectedCategory == nil ? "Выберите категорию" : nil
                    )

                    // 4. Основная информация
                    VStack(spacing: 0) {
                        HStack {
                            Text("Основная информация")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xs)

                        VStack(spacing: 0) {
                            // Название
                            VStack(spacing: 0) {
                                TextField("Название подписки", text: $description)
                                    .focused($isDescriptionFocused)
                                    .padding(AppSpacing.md)
                            }
                            .background(AppColors.cardBackground)
                            .clipShape(.rect(cornerRadius: AppRadius.md))

                            Divider()
                                .padding(.leading, AppSpacing.md)

                            // Иконка/Логотип
                            Button {
                                HapticManager.light()
                                showingIconPicker = true
                            } label: {
                                HStack(spacing: AppSpacing.md) {
                                    Text(String(localized: "iconPicker.title"))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    IconView(
                                        source: selectedIconSource,
                                        size: AppIconSize.xl
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(AppSpacing.md)
                            }
                            .background(AppColors.cardBackground)

                            Divider()
                                .padding(.leading, AppSpacing.md)

                            // Частота
                            VStack(spacing: AppSpacing.sm) {
                                HStack {
                                    Text("Частота")
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                }
                                SegmentedPickerView(
                                    title: "",
                                    selection: $selectedFrequency,
                                    options: RecurringFrequency.allCases.map { frequency in
                                        (label: frequency.displayName, value: frequency)
                                    }
                                )
                            }
                            .padding(AppSpacing.md)
                            .background(AppColors.cardBackground)

                            Divider()
                                .padding(.leading, AppSpacing.md)

                            // Дата начала
                            DatePicker("Дата начала", selection: $startDate, displayedComponents: .date)
                                .padding(AppSpacing.md)
                                .background(AppColors.cardBackground)
                        }
                        .background(AppColors.cardBackground)
                        .clipShape(.rect(cornerRadius: AppRadius.md))
                    }

                    // 5. Напоминания
                    VStack(spacing: 0) {
                        HStack {
                            Text("Напоминания")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xs)

                        VStack(spacing: 0) {
                            ForEach(reminderOptions, id: \.self) { offset in
                                VStack(spacing: 0) {
                                    Toggle(reminderText(offset), isOn: Binding(
                                        get: { selectedReminderOffsets.contains(offset) },
                                        set: { isOn in
                                            if isOn {
                                                selectedReminderOffsets.insert(offset)
                                            } else {
                                                selectedReminderOffsets.remove(offset)
                                            }
                                        }
                                    ))
                                    .padding(AppSpacing.md)

                                    if offset != reminderOptions.last {
                                        Divider()
                                            .padding(.leading, AppSpacing.md)
                                    }
                                }
                            }
                        }
                        .background(AppColors.cardBackground)
                        .clipShape(.rect(cornerRadius: AppRadius.md))
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .navigationTitle(subscription == nil ? "Новая подписка" : "Редактировать подписку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.light()
                        saveSubscription()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(description.isEmpty || amountText.isEmpty)
                }
            }
        }
        .onAppear {
            if let subscription = subscription {
                description = subscription.description
                amountText = NSDecimalNumber(decimal: subscription.amount).stringValue
                currency = subscription.currency
                selectedCategory = subscription.category.isEmpty ? nil : subscription.category
                selectedAccountId = subscription.accountId
                selectedFrequency = subscription.frequency
                if let date = DateFormatters.dateFormatter.date(from: subscription.startDate) {
                    startDate = date
                }
                selectedIconSource = subscription.iconSource
                selectedReminderOffsets = Set(subscription.reminderOffsets ?? [])
            } else {
                currency = transactionsViewModel.appSettings.baseCurrency
                if !availableCategories.isEmpty {
                    selectedCategory = availableCategories[0]
                }
                // Set first account as default
                if !transactionsViewModel.accounts.isEmpty {
                    selectedAccountId = transactionsViewModel.accounts[0].id
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $selectedIconSource)
        }
    }
    
    private func reminderText(_ days: Int) -> String {
        switch days {
        case 1: return "За 1 день"
        case 3: return "За 3 дня"
        case 7: return "За неделю"
        case 30: return "За месяц"
        default: return "За \(days) дней"
        }
    }
    
    private func saveSubscription() {
        // Validate required fields: description, amount, category, and account
        guard !description.isEmpty else {
            validationError = "Введите название подписки"
            return
        }

        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")),
              amount > 0 else {
            validationError = "Введите корректную сумму"
            return
        }

        guard let category = selectedCategory, !category.isEmpty else {
            validationError = "Выберите категорию"
            return
        }

        guard let accountId = selectedAccountId, !accountId.isEmpty else {
            validationError = "Выберите счёт оплаты"
            return
        }

        validationError = nil

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: startDate)

        let series = RecurringSeries(
            id: subscription?.id ?? UUID().uuidString,
            isActive: subscription?.isActive ?? true,
            amount: amount,
            currency: currency,
            category: category,
            subcategory: nil,
            description: description,
            accountId: accountId,
            targetAccountId: nil,
            frequency: selectedFrequency,
            startDate: dateString,
            lastGeneratedDate: subscription?.lastGeneratedDate,
            kind: .subscription,
            iconSource: selectedIconSource,
            reminderOffsets: selectedReminderOffsets.isEmpty ? nil : Array(selectedReminderOffsets).sorted(),
            status: subscription?.status ?? .active
        )

        onSave(series)
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionEditView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel,
        subscription: nil,
        onSave: { _ in },
        onCancel: {}
    )
}
