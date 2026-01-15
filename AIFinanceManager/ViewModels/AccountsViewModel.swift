//
//  AccountsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing accounts

import Foundation
import SwiftUI
import Combine

@MainActor
class AccountsViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var accounts: [Account] = []
    
    // MARK: - Private Properties
    
    private let repository: DataRepositoryProtocol
    private var initialAccountBalances: [String: Double] = [:]
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        self.accounts = repository.loadAccounts()
        
        // Инициализируем начальные балансы из загруженных счетов
        for account in accounts {
            if initialAccountBalances[account.id] == nil {
                initialAccountBalances[account.id] = account.balance
            }
        }
    }
    
    // MARK: - Account CRUD Operations
    
    func addAccount(name: String, balance: Double, currency: String, bankLogo: BankLogo = .none) {
        let account = Account(name: name, balance: balance, currency: currency, bankLogo: bankLogo)
        accounts.append(account)
        // Сохраняем начальный баланс
        initialAccountBalances[account.id] = balance
        repository.saveAccounts(accounts)
    }
    
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            // Обновляем начальный баланс при редактировании
            initialAccountBalances[account.id] = account.balance
            repository.saveAccounts(accounts)
        }
    }
    
    func deleteAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        initialAccountBalances.removeValue(forKey: account.id)
        repository.saveAccounts(accounts)
    }
    
    // MARK: - Account Balance Management
    
    /// Получить начальный баланс счета
    func getInitialBalance(for accountId: String) -> Double? {
        return initialAccountBalances[accountId]
    }
    
    /// Установить начальный баланс счета
    func setInitialBalance(_ balance: Double, for accountId: String) {
        initialAccountBalances[accountId] = balance
    }
    
    // MARK: - Transfer Operations
    
    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }
        
        let sourceAccount = accounts[sourceIndex]
        let _ = accounts[targetIndex]
        
        // Определяем валюту транзакции (используем валюту источника)
        let _ = sourceAccount.currency
        
        // Создаем транзакцию перевода
        // Note: Transaction creation should be handled by TransactionsViewModel
        // This method is kept for backward compatibility but should be refactored
        
        // Обновляем балансы (это будет пересчитано через recalculateAccountBalances в TransactionsViewModel)
        repository.saveAccounts(accounts)
    }
    
    // MARK: - Deposit Operations
    
    func addDeposit(
        name: String,
        balance: Double,
        currency: String,
        bankLogo: BankLogo = .none,
        principalBalance: Decimal,
        capitalizationEnabled: Bool,
        interestRateAnnual: Decimal,
        interestPostingDay: Int
    ) {
        let depositInfo = DepositInfo(
            bankName: name, // Используем name как bankName
            principalBalance: principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRateAnnual,
            interestPostingDay: interestPostingDay
        )
        
        let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
        let account = Account(
            name: name,
            balance: balance,
            currency: currency,
            bankLogo: bankLogo,
            depositInfo: depositInfo
        )
        
        accounts.append(account)
        initialAccountBalances[account.id] = balance
        repository.saveAccounts(accounts)
    }
    
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            if let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                initialAccountBalances[account.id] = balance
            }
            repository.saveAccounts(accounts)
        }
    }
    
    func deleteDeposit(_ account: Account) {
        deleteAccount(account)
    }
    
    // MARK: - Helper Methods
    
    /// Получить счет по ID
    func getAccount(by id: String) -> Account? {
        return accounts.first { $0.id == id }
    }
    
    /// Получить все депозиты
    var deposits: [Account] {
        return accounts.filter { $0.isDeposit }
    }
    
    /// Получить все обычные счета (не депозиты)
    var regularAccounts: [Account] {
        return accounts.filter { !$0.isDeposit }
    }
}
