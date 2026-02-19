//
//  AccountOperationService.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Service for account operations (transfers, deposits, withdrawals)
/// Extracted from TransactionsViewModel (lines 893-1017) to follow SRP
@MainActor
class AccountOperationService: AccountOperationServiceProtocol {

    // MARK: - AccountOperationServiceProtocol Implementation

    func transfer(
        from sourceId: String,
        to targetId: String,
        amount: Double,
        currency: String,
        date: String,
        description: String,
        accounts: inout [Account],
        allTransactions: inout [Transaction],
        balanceCoordinator: (any BalanceCoordinatorProtocol)?,
        saveCallback: () -> Void
    ) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }

        let sourceAccount = accounts[sourceIndex]
        let targetAccount = accounts[targetIndex]

        // Calculate target amount with currency conversion
        let targetAmount = convertCurrency(
            amount: amount,
            from: currency,
            to: targetAccount.currency
        )

        // Create transfer transaction
        let createdAt = Date().timeIntervalSince1970
        let id = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .internalTransfer,
            currency: currency,
            createdAt: createdAt
        )

        // Store converted amounts for the transfer
        let convertedAmountForSource: Double? = (currency != sourceAccount.currency) ? amount : nil
        let resolvedTargetCurrency = targetAccount.currency

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmountForSource,
            type: .internalTransfer,
            category: TransactionType.transferCategoryName,
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId,
            accountName: sourceAccount.name,
            targetAccountName: targetAccount.name,
            targetCurrency: resolvedTargetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )

        // Add transaction to list (sorted by date descending)
        allTransactions.append(transferTx)
        allTransactions.sort { $0.date > $1.date }

        // ✅ CRITICAL FIX: Update balances through BalanceCoordinator (Single Source of Truth)
        if let coordinator = balanceCoordinator {
            Task { @MainActor in
                await coordinator.updateForTransaction(
                    transferTx,
                    operation: .add(transferTx),
                    priority: .immediate
                )
            }
        }

        saveCallback()
    }

    // MARK: - Private Helpers

    /// Convert currency internally (not exposed in protocol)
    private func convertCurrency(
        amount: Double,
        from fromCurrency: String,
        to toCurrency: String
    ) -> Double {
        if fromCurrency == toCurrency {
            return amount
        } else if let converted = CurrencyConverter.convertSync(amount: amount, from: fromCurrency, to: toCurrency) {
            return converted
        } else {
            // Fallback to original amount if conversion fails
            return amount
        }
    }
}
