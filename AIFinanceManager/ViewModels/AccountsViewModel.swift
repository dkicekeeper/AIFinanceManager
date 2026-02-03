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

    // MARK: - Dependencies

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth
    /// Injected by AppCoordinator, optional for backward compatibility
    var balanceCoordinator: BalanceCoordinator?

    // MARK: - Private Properties

    private let repository: DataRepositoryProtocol
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        self.accounts = repository.loadAccounts()

        // MIGRATED: Register accounts with BalanceCoordinator (Single Source of Truth)
        syncInitialBalancesToCoordinator()
    }
    
    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        #if DEBUG
        print("🔄 [AccountsVM] reloadFromStorage called")
        print("   📊 Current accounts count: \(accounts.count)")
        #endif

        accounts = repository.loadAccounts()

        #if DEBUG
        print("   📊 After reload accounts count: \(accounts.count)")
        print("   ⚠️ About to call syncInitialBalancesToCoordinator - THIS WILL MARK ALL AS MANUAL")
        #endif

        // MIGRATED: Sync accounts with BalanceCoordinator after reload
        syncInitialBalancesToCoordinator()
    }
    
    // MARK: - Account CRUD Operations
    
    func addAccount(name: String, balance: Double, currency: String, bankLogo: BankLogo = .none, shouldCalculateFromTransactions: Bool = false) async {
        #if DEBUG
        print("🔍 [AccountsVM] addAccount called:")
        print("   📝 Name: \(name)")
        print("   💰 Balance: \(balance)")
        print("   🧮 shouldCalculateFromTransactions: \(shouldCalculateFromTransactions)")
        #endif

        let account = Account(
            name: name,
            balance: 0,  // DEPRECATED - не сохраняем рассчитанный баланс
            currency: currency,
            bankLogo: bankLogo,
            shouldCalculateFromTransactions: shouldCalculateFromTransactions,
            initialBalance: shouldCalculateFromTransactions ? 0.0 : balance
        )
        accounts.append(account)
        saveAccounts()

        // NEW: Register account with BalanceCoordinator (now synchronous)
        if let coordinator = balanceCoordinator {
            await coordinator.registerAccounts([account])
            // Используем initialBalance вместо balance
            let initialBal = account.initialBalance ?? 0.0
            await coordinator.setInitialBalance(initialBal, for: account.id)

            // If shouldCalculateFromTransactions is true, DON'T mark as manual
            // This allows the account balance to be calculated from transactions
            if !shouldCalculateFromTransactions {
                #if DEBUG
                print("   ✏️ [AccountsVM] Marking as manual: \(account.id)")
                #endif
                await coordinator.markAsManual(account.id)
            } else {
                #if DEBUG
                print("   🧮 [AccountsVM] NOT marking as manual - will calculate from transactions: \(account.id)")
                print("   ✅ [AccountsVM] Initial balance set to: \(balance)")
                #endif
            }
        }
    }
    
    func updateAccount(_ account: Account) {

        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let oldBalance = accounts[index].balance

            // Создаем новый массив вместо модификации элемента на месте
            // Это необходимо для корректной работы @Published property wrapper
            var newAccounts = accounts
            newAccounts[index] = account

            // Переприсваиваем весь массив для триггера @Published
            accounts = newAccounts
            // NOTE: @Published automatically sends objectWillChange notification

            saveAccounts()  // ✅ Sync save

            // NEW: Update BalanceCoordinator if balance changed
            if let coordinator = balanceCoordinator, abs(oldBalance - account.balance) > 0.001 {
                Task {
                    await coordinator.updateForAccount(account, newBalance: account.balance)
                    await coordinator.setInitialBalance(account.balance, for: account.id)
                    await coordinator.markAsManual(account.id)
                }
            }
        } else {
        }
    }
    
    func deleteAccount(_ account: Account, deleteTransactions: Bool = false) {
        accounts.removeAll { $0.id == account.id }
        saveAccounts()  // ✅ Sync save
        // Note: Transaction deletion is handled by the calling view

        // NEW: Remove account from BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.removeAccount(account.id)
            }
        }
    }
    
    // MARK: - Account Balance Management

    /// MIGRATED: Get initial balance from BalanceCoordinator (Single Source of Truth)
    func getInitialBalance(for accountId: String) -> Double? {
        // Direct access to BalanceCoordinator not possible (async)
        // Use account.balance as fallback for backward compatibility
        return accounts.first(where: { $0.id == accountId })?.balance
    }

    /// MIGRATED: Set initial balance via BalanceCoordinator (Single Source of Truth)
    func setInitialBalance(_ balance: Double, for accountId: String) {
        // Delegate to BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.setInitialBalance(balance, for: accountId)
            }
        }
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
            balance: 0,  // DEPRECATED - не сохраняем рассчитанный баланс
            currency: currency,
            bankLogo: bankLogo,
            depositInfo: depositInfo,
            shouldCalculateFromTransactions: false,  // Депозиты всегда manual
            initialBalance: balance
        )

        accounts.append(account)
        saveAccounts()  // ✅ Sync save

        // NEW: Register deposit with BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.registerAccounts([account])
                await coordinator.setInitialBalance(balance, for: account.id)
                if let depositInfo = account.depositInfo {
                    await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
                }
            }
        }
    }
    
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {

            // Создаем новый массив вместо модификации элемента на месте
            var newAccounts = accounts
            newAccounts[index] = account

            // Переприсваиваем весь массив для триггера @Published
            accounts = newAccounts
            // NOTE: @Published automatically sends objectWillChange notification

            saveAccounts()  // ✅ Sync save

            // NEW: Update deposit in BalanceCoordinator
            if let coordinator = balanceCoordinator, let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                Task {
                    await coordinator.updateForAccount(account, newBalance: balance)
                    await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
                    await coordinator.setInitialBalance(balance, for: account.id)
                }
            }
        }
    }
    
    func deleteDeposit(_ account: Account) {
        deleteAccount(account)
    }
    
    // MARK: - Helper Methods

    /// Синхронизирует initialAccountBalances с BalanceCoordinator
    /// Вызывается при инициализации и перезагрузке для обеспечения согласованности данных
    private func syncInitialBalancesToCoordinator() {
        guard let coordinator = balanceCoordinator else { return }

        #if DEBUG
        print("🔄 [AccountsVM] syncInitialBalancesToCoordinator called")
        print("   📊 Syncing \(accounts.count) accounts")
        #endif

        Task {
            // Register all accounts
            await coordinator.registerAccounts(accounts)

            // Set initial balances and modes based on account configuration
            for account in accounts {
                #if DEBUG
                print("   🔍 [AccountsVM] Processing account: \(account.name)")
                print("      💰 Initial Balance: \(account.initialBalance ?? 0)")
                print("      🧮 shouldCalculateFromTransactions: \(account.shouldCalculateFromTransactions)")
                #endif

                // Используем initialBalance вместо balance
                let initialBal = account.initialBalance ?? 0.0
                await coordinator.setInitialBalance(initialBal, for: account.id)

                // Only mark as manual if shouldCalculateFromTransactions is false
                if !account.shouldCalculateFromTransactions {
                    await coordinator.markAsManual(account.id)
                    #if DEBUG
                    print("      ✏️ [AccountsVM] Marked as MANUAL")
                    #endif
                } else {
                    #if DEBUG
                    print("      🧮 [AccountsVM] Will calculate from transactions")
                    #endif
                }
            }

            #if DEBUG
            print("✅ [AccountsVM] Synced \(accounts.count) accounts to BalanceCoordinator")
            #endif
        }
    }

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
