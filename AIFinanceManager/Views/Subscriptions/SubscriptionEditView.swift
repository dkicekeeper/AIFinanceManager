//
//  SubscriptionEditView.swift
//  AIFinanceManager
//
//  Migrated to new component library (Phase 3)
//  Uses: FormSection, FormTextField, IconPickerRow, FrequencyPickerView,
//        DatePickerRow, ReminderPickerView
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
    @State private var showingNotificationPermission = false
    @State private var validationError: String? = nil
    @FocusState private var isDescriptionFocused: Bool

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
                VStack(spacing: AppSpacing.md) {
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
                        emptyStateMessage: transactionsViewModel.accounts.isEmpty ?
                            String(localized: "account.noAccountsAvailable") : nil,
                        warningMessage: selectedAccountId == nil ?
                            String(localized: "account.selectAccount") : nil,
                        balanceCoordinator: transactionsViewModel.balanceCoordinator!
                    )

                    // 3. Category Selector
                    CategorySelectorView(
                        categories: availableCategories,
                        type: .expense,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $selectedCategory,
                        warningMessage: selectedCategory == nil ?
                            String(localized: "category.selectCategory") : nil
                    )

                    // 4. Basic Information Section
                    FormSection(
                        header: String(localized: "subscription.basicInfo"),
                        style: .card
                    ) {
                        // Name
                        TextField(
                            String(localized: "subscription.namePlaceholder"),
                            text: $description
                        )
                        .focused($isDescriptionFocused)
                        .padding(AppSpacing.md)
                        .formDivider()

                        // Icon/Logo Picker
                        IconPickerRow(
                            selectedSource: $selectedIconSource,
                            title: String(localized: "iconPicker.title")
                        )
                        .formDivider()

                        // Frequency
                        MenuPickerRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: String(localized: "common.frequency"),
                            selection: $selectedFrequency
                        )
                        .formDivider()

                        // Start Date
                        DatePickerRow(
                            title: String(localized: "common.startDate"),
                            selection: $startDate
                        )
                        .formDivider()

                        // Reminder
                        ReminderPickerView(
                            selectedOffsets: $selectedReminderOffsets,
                            title: String(localized: "subscription.reminders")
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .navigationTitle(subscription == nil ?
                String(localized: "subscription.newTitle") :
                String(localized: "subscription.editTitle")
            )
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
        .sheet(isPresented: $showingNotificationPermission) {
            NotificationPermissionView(
                onAllow: {
                    await NotificationPermissionManager.shared.requestAuthorization()
                },
                onSkip: { }
            )
        }
    }

    private func saveSubscription() {
        // Validate required fields: description, amount, category, and account
        guard !description.isEmpty else {
            validationError = String(localized: "error.subscriptionNameRequired")
            return
        }

        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")),
              amount > 0 else {
            validationError = String(localized: "error.invalidAmount")
            return
        }

        guard let category = selectedCategory, !category.isEmpty else {
            validationError = String(localized: "error.categoryRequired")
            return
        }

        guard let accountId = selectedAccountId, !accountId.isEmpty else {
            validationError = String(localized: "error.accountRequired")
            return
        }

        validationError = nil

        // Check if we should request notification permissions
        // Only ask when creating a new subscription with reminders
        if subscription == nil && !selectedReminderOffsets.isEmpty {
            Task {
                let manager = NotificationPermissionManager.shared
                await manager.checkAuthorizationStatus()

                if manager.shouldRequestPermission {
                    // Show permission request sheet
                    showingNotificationPermission = true
                }
            }
        }

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
