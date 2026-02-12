//
//  DepositsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing deposits and interest calculations

import Foundation
import SwiftUI
import Combine
import Observation

@Observable
@MainActor
class DepositsViewModel {
    // MARK: - Observable Properties

    var deposits: [Account] = []

    // MARK: - Dependencies

    let repository: DataRepositoryProtocol
    let accountsViewModel: AccountsViewModel

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth
    /// Injected by AppCoordinator
    var balanceCoordinator: BalanceCoordinator?
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol, accountsViewModel: AccountsViewModel) {
        self.repository = repository
        self.accountsViewModel = accountsViewModel
        updateDeposits()
    }
    
    // MARK: - Deposit Management
    
    private func updateDeposits() {
        deposits = accountsViewModel.accounts.filter { $0.isDeposit }
    }
    
    func addDeposit(
        name: String,
        currency: String,
        bankName: String,
        iconSource: IconSource?,
        principalBalance: Decimal,
        interestRateAnnual: Decimal,
        interestPostingDay: Int,
        capitalizationEnabled: Bool = true
    ) {
        accountsViewModel.addDeposit(
            name: name,
            balance: NSDecimalNumber(decimal: principalBalance).doubleValue,
            currency: currency,
            iconSource: iconSource,
            principalBalance: principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRateAnnual,
            interestPostingDay: interestPostingDay
        )
        updateDeposits()
    }
    
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        accountsViewModel.updateDeposit(account)
        updateDeposits()
    }
    
    func deleteDeposit(_ account: Account) {
        accountsViewModel.deleteDeposit(account)
        updateDeposits()
    }
    
    // MARK: - Interest Rate Management
    
    func addDepositRateChange(accountId: String, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              var depositInfo = account.depositInfo else {
            return
        }
        
        DepositInterestService.addRateChange(
            depositInfo: &depositInfo,
            effectiveFrom: effectiveFrom,
            annualRate: annualRate,
            note: note
        )
        
        account.depositInfo = depositInfo
        accountsViewModel.updateAccount(account)
        updateDeposits()
    }
    
    // MARK: - Interest Reconciliation
    
    /// Reconcile interest for all deposits
    /// Note: This requires access to allTransactions, which should be provided by TransactionsViewModel
    func reconcileAllDeposits(allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        for account in accountsViewModel.accounts where account.isDeposit {
            var updatedAccount = account
            DepositInterestService.reconcileDepositInterest(
                account: &updatedAccount,
                allTransactions: allTransactions,
                onTransactionCreated: onTransactionCreated
            )
            // Use updateAccount to ensure proper saving
            accountsViewModel.updateAccount(updatedAccount)
        }
        updateDeposits()
    }
    
    /// Reconcile interest for a specific deposit
    func reconcileDepositInterest(for accountId: String, allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              account.isDeposit else {
            return
        }
        
        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: allTransactions,
            onTransactionCreated: onTransactionCreated
        )
        // Use updateAccount to ensure proper saving
        accountsViewModel.updateAccount(account)
        updateDeposits()
    }
    
    // MARK: - Helper Methods
    
    /// Get deposit by ID
    func getDeposit(by id: String) -> Account? {
        return deposits.first { $0.id == id }
    }
    
    /// Calculate interest to today for a deposit
    func calculateInterestToToday(for accountId: String) -> Decimal? {
        guard let account = getDeposit(by: accountId),
              let depositInfo = account.depositInfo else {
            return nil
        }
        return DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
    }
    
    /// Get next posting date for a deposit
    func nextPostingDate(for accountId: String) -> Date? {
        guard let account = getDeposit(by: accountId),
              let depositInfo = account.depositInfo else {
            return nil
        }
        return DepositInterestService.nextPostingDate(depositInfo: depositInfo)
    }
}
