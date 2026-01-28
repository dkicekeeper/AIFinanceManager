//
//  AccountsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing accounts

import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class AccountsViewModel: ObservableObject, AccountBalanceServiceProtocol {
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
        accounts = repository.loadAccounts()

        // Обновляем начальные балансы
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
        // Сохраняем начальный баланс для корректного расчета в TransactionsViewModel
        initialAccountBalances[account.id] = balance
        saveAccounts()
    }
    
    func updateAccount(_ account: Account) {

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            _ = accounts[index].balance

            // Создаем новый массив вместо модификации элемента на месте
            // Это необходимо для корректной работы @Published property wrapper
            var newAccounts = accounts
            newAccounts[index] = account

            // Обновляем начальный баланс при редактировании
            initialAccountBalances[account.id] = account.balance


            // Переприсваиваем весь массив для триггера @Published
            accounts = newAccounts
            // NOTE: @Published automatically sends objectWillChange notification

            saveAccounts()  // ✅ Sync save
        } else {
        }
    }
    
    func deleteAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        initialAccountBalances.removeValue(forKey: account.id)
        saveAccounts()  // ✅ Sync save
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
        saveAccounts()  // ✅ Sync save
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
        saveAccounts()  // ✅ Sync save
    }
    
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {

            // Создаем новый массив вместо модификации элемента на месте
            var newAccounts = accounts
            newAccounts[index] = account

            if let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                initialAccountBalances[account.id] = balance
            }

            // Переприсваиваем весь массив для триггера @Published
            accounts = newAccounts
            // NOTE: @Published automatically sends objectWillChange notification

            saveAccounts()  // ✅ Sync save
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
        repository.saveAccounts(accounts)
    }

    /// Синхронно сохранить все счета (используется при импорте)
    func saveAllAccountsSync() {
        // Use repository to save synchronously
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveAccountsSync(accounts)
            } catch {
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            repository.saveAccounts(accounts)
        }
    }

    /// Синхронизировать балансы с обновленными счетами (вызывается из TransactionsViewModel)
    func syncAccountBalances(_ updatedAccounts: [Account]) {

        // Создаем новый массив вместо модификации элементов на месте
        // Это необходимо для корректной работы @Published property wrapper
        var newAccounts = accounts

        for updatedAccount in updatedAccounts {
            if let index = newAccounts.firstIndex(where: { $0.id == updatedAccount.id }) {
                newAccounts[index] = updatedAccount
            } else {
                // Аккаунт не найден - добавляем его (например, при импорте CSV)
                newAccounts.append(updatedAccount)
            }
        }

        // Переприсваиваем весь массив для триггера @Published
        accounts = newAccounts
    }
    
    // MARK: - Intelligent Account Ranking
    
    /// Получить счета, отсортированные по частоте использования с учетом контекста
    /// - Parameters:
    ///   - transactions: История транзакций
    ///   - type: Тип транзакции
    ///   - amount: Сумма транзакции (опционально)
    ///   - category: Категория транзакции (опционально)
    ///   - sourceAccountId: ID счета источника для переводов (опционально)
    /// - Returns: Отсортированный массив счетов
    func rankedAccounts(
        transactions: [Transaction],
        type: TransactionType,
        amount: Double? = nil,
        category: String? = nil,
        sourceAccountId: String? = nil
    ) -> [Account] {
        let context = AccountRankingContext(
            type: type,
            amount: amount,
            category: category,
            sourceAccountId: sourceAccountId
        )
        
        return AccountRankingService.rankAccounts(
            accounts: accounts,
            transactions: transactions,
            context: context
        )
    }
    
    /// Получить рекомендуемый счет для категории (адаптивное автоподставление)
    /// - Parameters:
    ///   - category: Категория транзакции
    ///   - transactions: История транзакций
    ///   - amount: Сумма транзакции (опционально)
    /// - Returns: Рекомендуемый счет или первый доступный
    func suggestedAccount(
        forCategory category: String,
        transactions: [Transaction],
        amount: Double? = nil
    ) -> Account? {
        return AccountRankingService.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            transactions: transactions,
            amount: amount
        )
    }
    
    // MARK: - Private Helpers
    
    /// Save accounts synchronously to prevent data loss on app termination
    private func saveAccounts() {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveAccountsSync(accounts)
            } catch {
                // Fallback to async save
                repository.saveAccounts(accounts)
            }
        } else {
            repository.saveAccounts(accounts)
        }
    }
}
