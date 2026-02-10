//
//  SubscriptionEditView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionEditView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    @ObservedObject var transactionStore: TransactionStore
    @ObservedObject var transactionsViewModel: TransactionsViewModel
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
    @State private var selectedBrandLogo: BankLogo? = nil
    @State private var selectedBrandName: String? = nil // Название бренда для logo.dev
    @State private var selectedIconName: String? = nil // SF Symbol иконка
    @State private var selectedReminderOffsets: Set<Int> = []
    @State private var showingLogoSearch = false
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
        EditSheetContainer(
            title: subscription == nil ? "Новая подписка" : "Редактировать подписку",
            isSaveDisabled: description.isEmpty || amountText.isEmpty,
            onSave: {
                saveSubscription()
            },
            onCancel: onCancel
        ) {
                // ✨ Amount Input - Reusable Component
                AmountInputView(
                    amount: $amountText,
                    selectedCurrency: $currency,
                    errorMessage: validationError,
                    onAmountChange: { _ in
                        validationError = nil
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: Text("Название")) {
                    TextField("Название подписки", text: $description)
                        .focused($isDescriptionFocused)
                }

                Section(header: Text("Логотип/Иконка")) {
                    Button(action: { showingLogoSearch = true }) {
                        HStack {
                            Text("Найти логотип")
                            Spacer()
                            if let brandName = selectedBrandName {
                                // Показываем предпросмотр логотипа
                                if let url = LogoDevConfig.logoURL(for: brandName) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(width: AppIconSize.lg, height: AppIconSize.lg)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: AppIconSize.lg, height: AppIconSize.lg)
                                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                                        case .failure(_):
                                            Image(systemName: "photo")
                                                .foregroundColor(AppColors.textSecondary)
                                        @unknown default:
                                            Image(systemName: "photo")
                                                .foregroundColor(AppColors.textSecondary)
                                        }
                                    }
                                } else {
                                    Image(systemName: "photo")
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                Text(brandName)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            } else if let logo = selectedBrandLogo {
                                logo.image(size: AppIconSize.lg)
                            } else if let iconName = selectedIconName {
                                Image(systemName: iconName)
                                    .foregroundColor(AppColors.textSecondary)
                                    .font(.system(size: AppIconSize.lg))
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(AppColors.textSecondary)
                                .font(AppTypography.caption)
                        }
                    }

                    Button(action: { showingIconPicker = true }) {
                        HStack {
                            Text("Выбрать иконку")
                            Spacer()
                            if let iconName = selectedIconName {
                                Image(systemName: iconName)
                                    .foregroundColor(AppColors.textSecondary)
                                    .font(.system(size: AppIconSize.lg))
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(AppColors.textSecondary)
                                .font(AppTypography.caption)
                        }
                    }
                }

                // ✨ Category Selector - Reusable Component
                Section(header: Text("Категория")) {
                    CategorySelectorView(
                        categories: availableCategories,
                        type: .expense,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $selectedCategory,
                        warningMessage: selectedCategory == nil ? "Выберите категорию" : nil
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // ✨ Account Selector - Reusable Component
                Section(header: Text("Счёт оплаты")) {
                    AccountSelectorView(
                        accounts: transactionsViewModel.accounts,
                        selectedAccountId: $selectedAccountId,
                        emptyStateMessage: transactionsViewModel.accounts.isEmpty ? "Нет доступных счетов" : nil,
                        warningMessage: selectedAccountId == nil ? "Выберите счёт" : nil,
                        balanceCoordinator: transactionsViewModel.balanceCoordinator!
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                Section(header: Text("Частота")) {
                    Picker("Частота", selection: $selectedFrequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Дата начала")) {
                    DatePicker("Дата начала", selection: $startDate, displayedComponents: .date)
                }
                
                Section(header: Text("Напоминания")) {
                    ForEach(reminderOptions, id: \.self) { offset in
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
                selectedBrandLogo = subscription.brandLogo
                selectedBrandName = subscription.brandId // brandId хранит название бренда для logo.dev
                // Если brandId начинается с "sf:" или "icon:", это иконка
                if let brandId = subscription.brandId, brandId.hasPrefix("sf:") {
                    selectedIconName = String(brandId.dropFirst(3))
                    selectedBrandName = nil
                } else if let brandId = subscription.brandId, brandId.hasPrefix("icon:") {
                    selectedIconName = String(brandId.dropFirst(5))
                    selectedBrandName = nil
                }
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
        .sheet(isPresented: $showingLogoSearch) {
            LogoSearchView(selectedBrandName: $selectedBrandName)
                .onDisappear {
                    // При выборе логотипа сбрасываем иконку
                    if selectedBrandName != nil {
                        selectedIconName = nil
                    }
                }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIconName: Binding(
                get: { selectedIconName ?? "creditcard.fill" },
                set: { newIcon in
                    selectedIconName = newIcon
                    // При выборе иконки сбрасываем логотип
                    selectedBrandName = nil
                    selectedBrandLogo = nil
                }
            ))
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
            brandLogo: selectedBrandLogo,
            brandId: selectedIconName != nil ? "sf:\(selectedIconName!)" : selectedBrandName, // Сохраняем иконку с префиксом или название бренда
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
