//
//  AccountRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Account-specific data persistence operations

import Foundation
import CoreData

/// Protocol for account repository operations
protocol AccountRepositoryProtocol {
    func loadAccounts() -> [Account]
    func saveAccounts(_ accounts: [Account])
    func saveAccountsSync(_ accounts: [Account]) throws
    func updateAccountBalance(accountId: String, balance: Double)
    func updateAccountBalances(_ balances: [String: Double])
    func loadAllAccountBalances() -> [String: Double]
}

/// CoreData implementation of AccountRepositoryProtocol
final class AccountRepository: AccountRepositoryProtocol {

    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator
    private let userDefaultsRepository: UserDefaultsRepository

    init(
        stack: CoreDataStack = .shared,
        saveCoordinator: CoreDataSaveCoordinator,
        userDefaultsRepository: UserDefaultsRepository = UserDefaultsRepository()
    ) {
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.userDefaultsRepository = userDefaultsRepository
    }

    // MARK: - Load Operations

    func loadAccounts() -> [Account] {
        PerformanceProfiler.start("AccountRepository.loadAccounts")

        let context = stack.viewContext
        let request = AccountEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(request)
            let accounts = entities.map { $0.toAccount() }

            PerformanceProfiler.end("AccountRepository.loadAccounts")

            return accounts
        } catch {
            PerformanceProfiler.end("AccountRepository.loadAccounts")

            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadAccounts()
        }
    }

    func loadAllAccountBalances() -> [String: Double] {
        let context = stack.viewContext
        let request = AccountEntity.fetchRequest()

        do {
            let entities = try context.fetch(request)
            var balances: [String: Double] = [:]

            for entity in entities {
                if let accountId = entity.id {
                    balances[accountId] = entity.balance
                }
            }

            #if DEBUG
            print("💾 [AccountRepository] Loaded \(balances.count) persisted balances")
            #endif

            return balances
        } catch {
            #if DEBUG
            print("❌ [AccountRepository] Failed to load balances: \(error)")
            #endif
            return [:]
        }
    }

    // MARK: - Save Operations

    func saveAccounts(_ accounts: [Account]) {

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("AccountRepository.saveAccounts")

            do {
                try await self.saveCoordinator.performSave(operation: "saveAccounts") { context in
                    try self.saveAccountsInternal(accounts, context: context)
                }

                PerformanceProfiler.end("AccountRepository.saveAccounts")

            } catch {
                PerformanceProfiler.end("AccountRepository.saveAccounts")
            }
        }
    }

    func saveAccountsSync(_ accounts: [Account]) throws {
        let context = stack.viewContext
        try saveAccountsInternal(accounts, context: context)

        // Save if there are changes
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: - Balance Update Operations

    func updateAccountBalance(accountId: String, balance: Double) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.saveCoordinator.performSave(operation: "updateAccountBalance") { context in
                    let fetchRequest = AccountEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", accountId)
                    fetchRequest.fetchLimit = 1

                    if let account = try context.fetch(fetchRequest).first {
                        context.perform {
                            account.balance = balance

                            #if DEBUG
                            print("💾 [AccountRepository] Updated balance for \(accountId): \(balance)")
                            #endif
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [AccountRepository] Failed to update balance for \(accountId): \(error)")
                #endif
            }
        }
    }

    func updateAccountBalances(_ balances: [String: Double]) {
        guard !balances.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.saveCoordinator.performSave(operation: "updateAccountBalances") { context in
                    let accountIds = Array(balances.keys)
                    let fetchRequest = AccountEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id IN %@", accountIds)

                    let accounts = try context.fetch(fetchRequest)

                    context.perform {
                        for account in accounts {
                            if let accountId = account.id, let newBalance = balances[accountId] {
                                account.balance = newBalance
                            }
                        }
                    }

                    #if DEBUG
                    print("💾 [AccountRepository] Batch updated \(accounts.count) account balances")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ [AccountRepository] Failed to batch update balances: \(error)")
                #endif
            }
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func saveAccountsInternal(_ accounts: [Account], context: NSManagedObjectContext) throws {
        // Fetch all existing accounts
        let fetchRequest = AccountEntity.fetchRequest()
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely, handling duplicates by keeping the first occurrence
        var existingDict: [String: AccountEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
                // Found duplicate - delete the extra entity
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        // Update or create accounts
        for account in accounts {
            keptIds.insert(account.id)

            if let existing = existingDict[account.id] {
                // Update existing
                context.perform {
                    existing.name = account.name
                    // ⚠️ CRITICAL FIX: Don't overwrite balance here - it's managed by BalanceCoordinator
                    // Only update balance when creating new accounts
                    existing.currency = account.currency
                    // Save iconSource as logo string (backward compatible)
                    if case .bankLogo(let bankLogo) = account.iconSource {
                        existing.logo = bankLogo.rawValue
                    } else {
                        existing.logo = BankLogo.none.rawValue
                    }
                    existing.isDeposit = account.isDeposit
                    existing.bankName = account.depositInfo?.bankName
                    existing.shouldCalculateFromTransactions = account.shouldCalculateFromTransactions
                }
            } else {
                // Create new
                _ = AccountEntity.from(account, context: context)
            }
        }

        // Delete accounts that no longer exist
        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }
}
