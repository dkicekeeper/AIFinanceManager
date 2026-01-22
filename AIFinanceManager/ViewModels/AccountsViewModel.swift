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
    
    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        print("🔄 [ACCOUNT] Reloading accounts from storage")
        accounts = repository.loadAccounts()

        print("📊 [ACCOUNT] Loaded \(accounts.count) accounts from storage")
        for account in accounts {
            print("   💰 '\(account.name)': balance = \(account.balance)")
        }

        // Обновляем начальные балансы
        for account in accounts {
            if initialAccountBalances[account.id] == nil {
                initialAccountBalances[account.id] = account.balance
            }
        }
        print("✅ [ACCOUNT] Reload from storage completed")
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
        print("📝 [ACCOUNT] Updating account: \(account.name) (ID: \(account.id))")
        print("💰 [ACCOUNT] New balance: \(account.balance)")

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let oldBalance = accounts[index].balance

            // Создаем новый массив вместо модификации элемента на месте
            // Это необходимо для корректной работы @Published property wrapper
            var newAccounts = accounts
            newAccounts[index] = account

            // Обновляем начальный баланс при редактировании
            initialAccountBalances[account.id] = account.balance

            print("✅ [ACCOUNT] Account updated: \(oldBalance) -> \(account.balance)")

            // Переприсваиваем весь массив для триггера @Published
            print("📢 [ACCOUNT] Reassigning accounts array to trigger @Published")
            accounts = newAccounts

            // Принудительно уведомляем SwiftUI об изменении
            print("📢 [ACCOUNT] Sending objectWillChange notification")
            objectWillChange.send()

            print("💾 [ACCOUNT] Saving accounts to repository")
            repository.saveAccounts(accounts)
            print("✅ [ACCOUNT] Accounts saved")
        } else {
            print("⚠️ [ACCOUNT] Account with ID \(account.id) not found")
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
            print("📝 [ACCOUNT] Updating deposit: \(account.name) (ID: \(account.id))")

            // Создаем новый массив вместо модификации элемента на месте
            var newAccounts = accounts
            newAccounts[index] = account

            if let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                initialAccountBalances[account.id] = balance
                print("💰 [ACCOUNT] Deposit balance updated to: \(balance)")
            }

            // Переприсваиваем весь массив для триггера @Published
            print("📢 [ACCOUNT] Reassigning accounts array to trigger @Published")
            accounts = newAccounts

            // Принудительно уведомляем SwiftUI об изменении
            print("📢 [ACCOUNT] Sending objectWillChange notification")
            objectWillChange.send()

            repository.saveAccounts(accounts)
            print("✅ [ACCOUNT] Deposit saved")
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
    
    /// Сохранить все счета (используется после массового обновления балансов)
    func saveAllAccounts() {
        print("💾 [ACCOUNT] Saving all accounts via repository")
        for account in accounts {
            print("   💰 '\(account.name)': balance = \(account.balance)")
        }
        repository.saveAccounts(accounts)
        print("✅ [ACCOUNT] All accounts saved")
    }

    /// Синхронно сохранить все счета (используется при импорте)
    func saveAllAccountsSync() {
        print("💾 [ACCOUNT] Saving all accounts synchronously")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: "accounts")
            UserDefaults.standard.synchronize()
            print("✅ [ACCOUNT] All accounts saved synchronously")
        } else {
            print("❌ [ACCOUNT] Failed to encode accounts")
        }
    }

    /// Синхронизировать балансы с обновленными счетами (вызывается из TransactionsViewModel)
    func syncAccountBalances(_ updatedAccounts: [Account]) {
        print("🔄 [ACCOUNT] Syncing account balances from TransactionsViewModel")
        print("📊 [ACCOUNT] Current accounts count: \(accounts.count)")
        print("📊 [ACCOUNT] Updated accounts count: \(updatedAccounts.count)")

        // Создаем новый массив вместо модификации элементов на месте
        // Это необходимо для корректной работы @Published property wrapper
        var newAccounts = accounts

        for updatedAccount in updatedAccounts {
            if let index = newAccounts.firstIndex(where: { $0.id == updatedAccount.id }) {
                let oldBalance = newAccounts[index].balance
                newAccounts[index] = updatedAccount
                print("   🔄 '\(updatedAccount.name)': \(oldBalance) -> \(updatedAccount.balance)")
            } else {
                print("   ⚠️ Account '\(updatedAccount.name)' (ID: \(updatedAccount.id)) not found in AccountsViewModel")
            }
        }

        // Переприсваиваем весь массив для триггера @Published
        print("📢 [ACCOUNT] Reassigning accounts array to trigger @Published")
        accounts = newAccounts

        // Принудительно уведомляем SwiftUI об изменении
        print("📢 [ACCOUNT] Sending objectWillChange notification")
        objectWillChange.send()

        print("✅ [ACCOUNT] Balance sync completed")
    }
}
