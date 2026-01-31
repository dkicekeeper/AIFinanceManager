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
        accountBalanceService: AccountBalanceServiceProtocol,
        saveCallback: () -> Void
    ) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }

        // CRITICAL: Create new array instead of modifying in-place
        // This is necessary for @Published property wrapper to trigger updates
        var newAccounts = accounts

        // Deduct from source account (with deposit handling)
        deduct(from: &newAccounts[sourceIndex], amount: amount)

        // Calculate target amount with currency conversion
        let targetAccount = newAccounts[targetIndex]
        let targetAmount = convertCurrency(
            amount: amount,
            from: currency,
            to: targetAccount.currency
        )

        // Add to target account (with deposit handling)
        add(to: &newAccounts[targetIndex], amount: targetAmount)

        // Update accounts reference
        accounts = newAccounts

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
        let sourceAccount = newAccounts[sourceIndex]
        let convertedAmountForSource: Double? = (currency != sourceAccount.currency) ? amount : nil
        let resolvedTargetCurrency = newAccounts[targetIndex].currency

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmountForSource,
            type: .internalTransfer,
            category: String(localized: "transactionForm.transfer"),
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId,
            accountName: newAccounts[sourceIndex].name,
            targetAccountName: newAccounts[targetIndex].name,
            targetCurrency: resolvedTargetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )

        // Insert transaction sorted by date (descending)
        allTransactions.append(transferTx)
        allTransactions.sort { $0.date > $1.date }

        // Sync balances and save
        accountBalanceService.syncAccountBalances(accounts)
        saveCallback()
    }

    func deduct(
        from account: inout Account,
        amount: Double
    ) {
        account.balance -= amount

        if var depositInfo = account.depositInfo {
            let amountDecimal = Decimal(amount)

            if !depositInfo.capitalizationEnabled && depositInfo.interestAccruedNotCapitalized > 0 {
                // Deduct from interest first, then principal
                if amountDecimal <= depositInfo.interestAccruedNotCapitalized {
                    depositInfo.interestAccruedNotCapitalized -= amountDecimal
                } else {
                    let remaining = amountDecimal - depositInfo.interestAccruedNotCapitalized
                    depositInfo.interestAccruedNotCapitalized = 0
                    depositInfo.principalBalance -= remaining
                }
            } else {
                // Deduct directly from principal
                depositInfo.principalBalance -= amountDecimal
            }

            account.depositInfo = depositInfo

            // Recalculate total balance
            var totalBalance: Decimal = depositInfo.principalBalance
            if !depositInfo.capitalizationEnabled {
                totalBalance += depositInfo.interestAccruedNotCapitalized
            }
            account.balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        }
    }

    func add(
        to account: inout Account,
        amount: Double
    ) {
        if var depositInfo = account.depositInfo {
            let amountDecimal = Decimal(amount)

            // Add to principal balance
            depositInfo.principalBalance += amountDecimal
            account.depositInfo = depositInfo

            // Recalculate total balance
            var totalBalance: Decimal = depositInfo.principalBalance
            if !depositInfo.capitalizationEnabled {
                totalBalance += depositInfo.interestAccruedNotCapitalized
            }
            account.balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            // Regular account - simple addition
            account.balance += amount
        }
    }

    func convertCurrency(
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
