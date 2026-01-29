//
//  SubscriptionEditView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionEditView: View {
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    let subscription: RecurringSeries?
    let onSave: (RecurringSeries) -> Void
    let onCancel: () -> Void
    
    @State private var description: String = ""
    @State private var amountText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedCategory: String = ""
    @State private var selectedAccountId: String? = nil
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var selectedBrandLogo: BankLogo? = nil
    @State private var selectedBrandName: String? = nil // Название бренда для logo.dev
    @State private var selectedIconName: String? = nil // SF Symbol иконка
    @State private var selectedReminderOffsets: Set<Int> = []
    @State private var showingLogoSearch = false
    @State private var showingIconPicker = false
    @FocusState private var isDescriptionFocused: Bool
    
    private let currencies = ["USD", "EUR", "KZT", "RUB", "GBP"]
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
        return Array(categories).sorted()
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
                
                Section(header: Text("Сумма")) {
                    HStack {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                        
                        Picker("Валюта", selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(Formatting.currencySymbol(for: curr)).tag(curr)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                Section(header: Text("Категория")) {
                    Picker("Категория", selection: $selectedCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }
                
                if !transactionsViewModel.accounts.isEmpty {
                    Section(header: Text("Счёт оплаты")) {
                        Picker("Счёт", selection: $selectedAccountId) {
                            Text("Без счёта").tag(nil as String?)
                            ForEach(transactionsViewModel.accounts) { account in
                                Text(account.name).tag(account.id as String?)
                            }
                        }
                    }
                }
                
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
                selectedCategory = subscription.category
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
        guard !description.isEmpty,
              let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              !selectedCategory.isEmpty else {
            return
        }
        
        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: startDate)
        
        let series = RecurringSeries(
            id: subscription?.id ?? UUID().uuidString,
            isActive: subscription?.isActive ?? true,
            amount: amount,
            currency: currency,
            category: selectedCategory,
            subcategory: nil,
            description: description,
            accountId: selectedAccountId,
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
        subscriptionsViewModel: coordinator.subscriptionsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        subscription: nil,
        onSave: { _ in },
        onCancel: {}
    )
}
