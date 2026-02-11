//
//  AddTransactionModal.swift
//  AIFinanceManager
//
//  Modal form for adding a transaction from the QuickAdd category grid.
//  Refactored to use AddTransactionCoordinator for business logic.
//

import SwiftUI

struct AddTransactionModal: View {

    // MARK: - Coordinator

    @State private var coordinator: AddTransactionCoordinator

    // MARK: - Environment

    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - State

    @State private var validationError: String?
    @State private var isSaving = false
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingCategoryHistory = false

    // MARK: - Callbacks

    let onDismiss: () -> Void

    // MARK: - Initialization

    init(
        category: String,
        type: TransactionType,
        currency: String,
        accounts: [Account],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        onDismiss: @escaping () -> Void
    ) {
        // ✅ REFACTORED: TransactionStore now passed directly, not via @EnvironmentObject
        _coordinator = State(initialValue: AddTransactionCoordinator(
            category: category,
            type: type,
            currency: currency,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore
        ))
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                formContent
                    .sheet(isPresented: $showingSubcategorySearch) {
                        subcategorySearchSheet
                    }
            }
            .navigationTitle(coordinator.formData.category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .dateButtonsSafeArea(
                selectedDate: $coordinator.formData.selectedDate,
                isDisabled: isSaving,
                onSave: { date in
                    coordinator.formData.selectedDate = date
                    Task { await saveTransaction() }
                }
            )
            .overlay(overlayContent)
            .sheet(isPresented: $showingCategoryHistory) {
                categoryHistorySheet
            }
            .onChange(of: coordinator.formData.accountId) { _, _ in
                coordinator.updateCurrencyForSelectedAccount()
            }
            .task {
                // ✅ REFACTORED: Simplified account suggestion
                // SwiftUI's .task{} automatically handles lifecycle
                if coordinator.formData.accountId == nil {
                    coordinator.formData.accountId = await coordinator.suggestedAccountId()
                    coordinator.updateCurrencyForSelectedAccount()
                } else {
                    coordinator.updateCurrencyForSelectedAccount()
                }
            }
        }
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                AmountInputView(
                    amount: $coordinator.formData.amountText,
                    selectedCurrency: $coordinator.formData.currency,
                    errorMessage: validationError,
                    baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
                    onAmountChange: { _ in
                        validationError = nil
                    }
                )

                if !coordinator.rankedAccounts().isEmpty {
                    AccountSelectorView(
                        accounts: coordinator.rankedAccounts(),
                        // ✅ PERFORMANCE FIX: Simple binding - no heavy computation in get
                        // Suggested account is set asynchronously in onAppear
                        selectedAccountId: $coordinator.formData.accountId,
                        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
                    )
                }

                if !coordinator.availableSubcategories().isEmpty {
                    SubcategorySelectorView(
                        categoriesViewModel: coordinator.categoriesViewModel,
                        categoryId: categoryId,
                        selectedSubcategoryIds: $coordinator.formData.subcategoryIds,
                        onSearchTap: {
                            showingSubcategorySearch = true
                        }
                    )
                }

                RecurringToggleView(
                    isRecurring: $coordinator.formData.isRecurring,
                    selectedFrequency: $coordinator.formData.frequency,
                    toggleTitle: String(localized: "quickAdd.makeRecurring"),
                    frequencyTitle: String(localized: "quickAdd.frequency")
                )

                DescriptionTextField(
                    text: $coordinator.formData.description,
                    placeholder: String(localized: "quickAdd.descriptionPlaceholder")
                )
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingCategoryHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
    }

    // MARK: - Overlay

    private var overlayContent: some View {
        Group {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }

    // MARK: - Sheets

    private var subcategorySearchSheet: some View {
        SubcategorySearchView(
            categoriesViewModel: coordinator.categoriesViewModel,
            categoryId: categoryId ?? "",
            selectedSubcategoryIds: $coordinator.formData.subcategoryIds,
            searchText: $subcategorySearchText
        )
        .onAppear {
            subcategorySearchText = ""
        }
    }

    private var categoryHistorySheet: some View {
        NavigationStack {
            HistoryView(
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                initialCategory: coordinator.formData.category
            )
            .environment(timeFilterManager)
        }
    }

    // MARK: - Private Methods

    private var categoryId: String? {
        coordinator.categoriesViewModel.customCategories.first {
            $0.name == coordinator.formData.category
        }?.id
    }

    private func saveTransaction() async {
        isSaving = true
        validationError = nil

        let result = await coordinator.save()

        isSaving = false

        if result.isValid {
            HapticManager.success()
            onDismiss()
        } else {
            validationError = result.errors.first?.localizedDescription
            HapticManager.error()
        }
    }
}
