//
//  AddTransactionCoordinator.swift
//  AIFinanceManager
//
//  Coordinator for AddTransactionModal.
//  Handles transaction creation with form validation and currency conversion.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AddTransactionCoordinator: ObservableObject {

    // MARK: - Dependencies

    // Internal access for temporary exposure during migration
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    private let formService: TransactionFormServiceProtocol

    // MARK: - Published State

    @Published var formData: TransactionFormData

    // MARK: - Private State

    private var _cachedSuggestedAccountId: String?
    private var _hasCachedSuggestion = false

    // MARK: - Initialization

    init(
        category: String,
        type: TransactionType,
        currency: String,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        formService: TransactionFormServiceProtocol? = nil
    ) {
        // ✅ PERFORMANCE: Don't compute suggested account in init
        // Deferred to lazy computed property to make sheet opening instant
        self.formData = TransactionFormData(
            category: category,
            type: type,
            currency: currency,
            suggestedAccountId: nil  // Will be computed on-demand
        )

        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        // Create service inside @MainActor context if not provided
        self.formService = formService ?? TransactionFormService()
    }

    // MARK: - Public Methods

    /// Get suggested account ID (sync - returns cached value or nil)
    /// Use computeSuggestedAccountIdAsync() for initial computation
    var suggestedAccountId: String? {
        // Only return cached value - don't compute synchronously
        guard _hasCachedSuggestion else { return nil }
        return _cachedSuggestedAccountId
    }

    /// Compute suggested account ID asynchronously (call once on appear)
    func computeSuggestedAccountIdAsync() async -> String? {
        // Return cached value if already computed
        guard !_hasCachedSuggestion else {
            return _cachedSuggestedAccountId
        }

        // ✅ PERFORMANCE: Compute on background thread to avoid blocking UI
        let result: String? = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }

            let suggested = await MainActor.run {
                self.accountsViewModel.suggestedAccount(
                    forCategory: self.formData.category,
                    transactions: self.transactionsViewModel.allTransactions,
                    amount: self.formData.amountDouble
                )
            }

            return await MainActor.run {
                suggested?.id ?? self.accountsViewModel.accounts.first?.id
            }
        }.value

        // Cache the result
        _cachedSuggestedAccountId = result
        _hasCachedSuggestion = true

        return result
    }

    /// Get accounts sorted by balance (fast, no transaction scanning needed)
    func rankedAccounts() -> [Account] {
        // Simply sort by balance - instant and no need to scan transactions!
        guard let balanceCoordinator = accountsViewModel.balanceCoordinator else {
            return accountsViewModel.accounts
        }

        let balances = balanceCoordinator.balances

        return accountsViewModel.accounts.sorted { account1, account2 in
            // Deposits at the end
            if account1.isDeposit != account2.isDeposit {
                return !account1.isDeposit
            }
            // Higher balance first
            let balance1 = balances[account1.id] ?? 0
            let balance2 = balances[account2.id] ?? 0
            return balance1 > balance2
        }
    }

    /// Get available subcategories for current category
    func availableSubcategories() -> [Subcategory] {
        guard let categoryId = categoriesViewModel.customCategories.first(where: {
            $0.name == formData.category
        })?.id else {
            return []
        }

        return categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }

    /// Update currency when account selection changes
    func updateCurrencyForSelectedAccount() {
        guard let accountId = formData.accountId,
              let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) else {
            return
        }

        formData.currency = account.currency
    }

    /// Save transaction
    func save() async -> ValidationResult {
        let accounts = accountsViewModel.accounts

        // Step 1: Validate form data
        let validationResult = formService.validate(formData, accounts: accounts)
        guard validationResult.isValid else {
            return validationResult
        }

        guard let account = accounts.first(where: { $0.id == formData.accountId }) else {
            return ValidationResult(isValid: false, errors: [.accountNotFound])
        }

        // Step 2: Handle recurring series if enabled
        if formData.isRecurring {
            createRecurringSeries()

            // If future date, only create series (not individual transaction)
            if formService.isFutureDate(formData.selectedDate) {
                return .valid
            }
        }

        // Step 3: Convert currency to base currency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let conversionResult = await formService.convertCurrency(
            amount: formData.parsedAmount!,
            from: formData.currency,
            to: baseCurrency,
            baseCurrency: baseCurrency
        )

        // Step 4: Calculate target amounts (for different currency scenarios)
        let targetAmounts = await formService.calculateTargetAmounts(
            amount: formData.parsedAmount!,
            currency: formData.currency,
            account: account,
            baseCurrency: baseCurrency
        )

        // Step 5: Create and add transaction
        let transaction = createTransaction(
            convertedAmount: conversionResult.convertedAmount,
            targetAmounts: targetAmounts
        )

        transactionsViewModel.addTransaction(transaction)

        // Step 6: Link subcategories if any selected
        if !formData.subcategoryIds.isEmpty {
            linkSubcategories(to: transaction)
        }

        return .valid
    }

    // MARK: - Private Methods

    private func createRecurringSeries() {
        _ = transactionsViewModel.createRecurringSeries(
            amount: formData.parsedAmount!,
            currency: formData.currency,
            category: formData.category,
            subcategory: nil,
            description: formData.description,
            accountId: formData.accountId!,
            targetAccountId: nil,
            frequency: formData.frequency,
            startDate: DateFormatters.dateFormatter.string(from: formData.selectedDate)
        )
    }

    private func createTransaction(
        convertedAmount: Double?,
        targetAmounts: TargetAmounts
    ) -> Transaction {
        Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: formData.selectedDate),
            description: formData.description,
            amount: formData.amountDouble!,
            currency: formData.currency,
            convertedAmount: convertedAmount,
            type: formData.type,
            category: formData.category,
            subcategory: nil,
            accountId: formData.accountId!,
            targetAccountId: nil,
            targetCurrency: targetAmounts.targetCurrency,
            targetAmount: targetAmounts.targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )
    }

    private func linkSubcategories(to transaction: Transaction) {
        // Find the added transaction in the list
        let addedTransaction = transactionsViewModel.allTransactions.first { tx in
            tx.date == DateFormatters.dateFormatter.string(from: formData.selectedDate) &&
            tx.description == formData.description &&
            tx.amount == formData.amountDouble &&
            tx.category == formData.category &&
            tx.accountId == formData.accountId &&
            tx.type == formData.type
        }

        if let transactionId = addedTransaction?.id {
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: transactionId,
                subcategoryIds: Array(formData.subcategoryIds)
            )
        }
    }
}
