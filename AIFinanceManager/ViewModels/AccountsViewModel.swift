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
class AccountsViewModel: ObservableObject {
    // MARK: - Published Properties

    /// PHASE 3: Accounts are now observed from TransactionStore (Single Source of Truth)
    /// This is a computed property - ViewModels no longer own the data
    @Published var accounts: [Account] = []

    // MARK: - Dependencies

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth
    /// Injected by AppCoordinator, optional for backward compatibility
    var balanceCoordinator: BalanceCoordinator?

    /// PHASE 3: TransactionStore as Single Source of Truth for accounts
    /// ViewModels observe this instead of owning data
    weak var transactionStore: TransactionStore?

    // MARK: - Private Properties

    private let repository: DataRepositoryProtocol
    private var accountsSubscription: AnyCancellable?

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        // PHASE 3: Don't load accounts here anymore - will be synced from TransactionStore
        // self.accounts = repository.loadAccounts()
    }

    /// PHASE 3: Setup subscription to TransactionStore.$accounts
    /// Called by AppCoordinator after TransactionStore is initialized
    func setupTransactionStoreObserver() {
        guard let transactionStore = transactionStore else {
            #if DEBUG
            print("⚠️ [AccountsVM] TransactionStore not set, cannot setup observer")
            #endif
            return
        }

        accountsSubscription = transactionStore.$accounts
            .sink { [weak self] updatedAccounts in
                guard let self = self else { return }
                self.accounts = updatedAccounts

                #if DEBUG
                print("✅ [AccountsVM] Received \(updatedAccounts.count) accounts from TransactionStore")
                #endif

                // MIGRATED: Register accounts with BalanceCoordinator (Single Source of Truth)
                self.syncInitialBalancesToCoordinator()
            }

        #if DEBUG
        print("✅ [AccountsVM] Setup TransactionStore observer")
        #endif
    }
    
    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        #if DEBUG
        print("🔄 [AccountsVM] reloadFromStorage called")
        print("   📊 Current accounts count: \(accounts.count)")
        #endif

        // PHASE 3: TransactionStore is the owner - it will reload and publish to observers
        // No need to reload here - accounts will be updated via subscription
        // Just trigger syncInitialBalancesToCoordinator when accounts change

        #if DEBUG
        print("   ⚠️ About to call syncInitialBalancesToCoordinator - THIS WILL MARK ALL AS MANUAL")
        #endif

        // MIGRATED: Sync accounts with BalanceCoordinator after reload
        syncInitialBalancesToCoordinator()
    }
    
    // MARK: - Account CRUD Operations
    
    func addAccount(name: String, initialBalance: Double, currency: String, bankLogo: BankLogo = .none, shouldCalculateFromTransactions: Bool = false) async {
        #if DEBUG
        print("🔍 [AccountsVM] addAccount called:")
        print("   📝 Name: \(name)")
        print("   💰 InitialBalance: \(initialBalance)")
        print("   🧮 shouldCalculateFromTransactions: \(shouldCalculateFromTransactions)")
        #endif

        let account = Account(
            name: name,
            currency: currency,
            bankLogo: bankLogo,
            shouldCalculateFromTransactions: shouldCalculateFromTransactions,
            initialBalance: shouldCalculateFromTransactions ? 0.0 : initialBalance
        )

        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.addAccount(account)

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
                print("   ✅ [AccountsVM] Initial balance set to: \(initialBalance)")
                #endif
            }
        }
    }
    
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let oldInitialBalance = accounts[index].initialBalance ?? 0

            // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
            transactionStore?.updateAccount(account)

            // NEW: Update BalanceCoordinator if initialBalance changed
            let newInitialBalance = account.initialBalance ?? 0
            if let coordinator = balanceCoordinator, abs(oldInitialBalance - newInitialBalance) > 0.001 {
                Task {
                    await coordinator.setInitialBalance(newInitialBalance, for: account.id)
                    await coordinator.markAsManual(account.id)
                }
            }
        } else {
            #if DEBUG
            print("⚠️ [AccountsVM] Account not found for update: \(account.id)")
            #endif
        }
    }
    
    func deleteAccount(_ account: Account, deleteTransactions: Bool = false) {
        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.deleteAccount(account.id)
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
        // Use account.initialBalance as fallback for backward compatibility
        return accounts.first(where: { $0.id == accountId })?.initialBalance
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

        // PHASE 3: No need to save - TransactionStore handles persistence
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
            currency: currency,
            bankLogo: bankLogo,
            depositInfo: depositInfo,
            shouldCalculateFromTransactions: false,  // Депозиты всегда manual
            initialBalance: balance
        )

        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.addAccount(account)

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
            // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
            transactionStore?.updateAccount(account)

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
    /// PHASE 3: Deprecated - TransactionStore handles persistence
    func saveAllAccounts() {
        #if DEBUG
        print("⚠️ [AccountsVM] saveAllAccounts is deprecated - TransactionStore handles persistence")
        #endif
    }

    /// Синхронно сохранить все счета (используется при импорте)
    /// PHASE 3: Deprecated - TransactionStore handles persistence
    func saveAllAccountsSync() {
        #if DEBUG
        print("⚠️ [AccountsVM] saveAllAccountsSync is deprecated - TransactionStore handles persistence")
        #endif
    }

    // MIGRATED: syncAccountBalances removed - now managed by BalanceCoordinator (Single Source of Truth)
    // Balances are no longer synced manually between ViewModels
    // All balance updates go through BalanceCoordinator.updateForTransaction()


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
    // PHASE 3: saveAccounts removed - TransactionStore handles persistence
}
