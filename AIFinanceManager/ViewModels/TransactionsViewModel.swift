//
//  TransactionsViewModel.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var accounts: [Account] = []
    @Published var customCategories: [CustomCategory] = []
    @Published var dateFilter: DateFilter = DateFilter()
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let storageKeyTransactions = "allTransactions"
    private let storageKeyRules = "categoryRules"
    private let storageKeyAccounts = "accounts"
    private let storageKeyCustomCategories = "customCategories"
    
    init() {
        loadFromStorage()
    }
    
    var filteredTransactions: [Transaction] {
        let transactions = applyRules(to: allTransactions)
        
        guard let startDate = dateFilter.startDate,
              let endDate = dateFilter.endDate else {
            return transactions
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return transactions.filter { transaction in
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= startDate && transactionDate <= endDate
        }
    }
    
    var summary: Summary {
        let filtered = filteredTransactions
        let totalIncome = filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpenses = filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let totalInternal = filtered.filter { $0.type == .internalTransfer }.reduce(0) { $0 + $1.amount }
        
        let currency = allTransactions.first?.currency ?? "USD"
        let dates = allTransactions.map { $0.date }.sorted()
        
        return Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: currency,
            startDate: dates.first ?? "",
            endDate: dates.last ?? ""
        )
    }
    
    var categoryExpenses: [String: CategoryExpense] {
        let filtered = filteredTransactions.filter { $0.type == .expense }
        var result: [String: CategoryExpense] = [:]
        
        for transaction in filtered {
            let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category
            if result[category] == nil {
                result[category] = CategoryExpense(total: 0, subcategories: [:])
            }
            var expense = result[category]!
            expense.total += transaction.amount
            
            if let subcategory = transaction.subcategory {
                expense.subcategories[subcategory, default: 0] += transaction.amount
            }
            
            result[category] = expense
        }
        
        return result
    }
    
    var popularCategories: [String] {
        Array(categoryExpenses.keys)
            .sorted { categoryExpenses[$0]?.total ?? 0 > categoryExpenses[$1]?.total ?? 0 }
    }
    
    var uniqueCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }
        return Array(categories).sorted()
    }
    
    func addTransactions(_ newTransactions: [Transaction]) {
        let transactionsWithRules = applyRules(to: newTransactions)
        
        // Remove duplicates
        let existingIDs = Set(allTransactions.map { $0.id })
        let uniqueNew = transactionsWithRules.filter { !existingIDs.contains($0.id) }
        
        if !uniqueNew.isEmpty {
            allTransactions.append(contentsOf: uniqueNew)
            allTransactions.sort { $0.date > $1.date }
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        let transactionWithID: Transaction
        if transaction.id.isEmpty {
            let id = TransactionIDGenerator.generateID(
                date: transaction.date,
                description: transaction.description,
                amount: transaction.amount,
                type: transaction.type,
                currency: transaction.currency
            )
            transactionWithID = Transaction(
                id: id,
                date: transaction.date,
                time: transaction.time,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                type: transaction.type,
                category: transaction.category,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId
            )
        } else {
            transactionWithID = transaction
        }
        
        let transactionsWithRules = applyRules(to: [transactionWithID])
        let existingIDs = Set(allTransactions.map { $0.id })
        
        if !existingIDs.contains(transactionWithID.id) {
            allTransactions.append(contentsOf: transactionsWithRules)
            allTransactions.sort { $0.date > $1.date }
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    func updateTransactionCategory(_ transactionId: String, category: String, subcategory: String?) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transactionId }) else {
            return
        }
        
        let transaction = allTransactions[index]
        
        // Create and save rule
        let newRule = CategoryRule(
            description: transaction.description,
            category: category,
            subcategory: subcategory
        )
        
        categoryRules.removeAll { $0.description.lowercased() == newRule.description.lowercased() }
        categoryRules.append(newRule)
        
        // Apply rule to all matching transactions
        for i in allTransactions.indices {
            if allTransactions[i].description.lowercased() == newRule.description.lowercased() {
                allTransactions[i] = Transaction(
                    id: allTransactions[i].id,
                    date: allTransactions[i].date,
                    time: allTransactions[i].time,
                    description: allTransactions[i].description,
                    amount: allTransactions[i].amount,
                    currency: allTransactions[i].currency,
                    type: allTransactions[i].type,
                    category: category,
                    subcategory: subcategory,
                    accountId: allTransactions[i].accountId,
                    targetAccountId: allTransactions[i].targetAccountId
                )
            }
        }
        
        saveToStorage()
    }
    
    func clearHistory() {
        allTransactions = []
        categoryRules = []
        accounts = []
        saveToStorage()
    }

    // MARK: - Custom Categories
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        saveToStorage()
    }
    
    func updateCategory(_ category: CustomCategory) {
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
            saveToStorage()
        }
    }
    
    func deleteCategory(_ category: CustomCategory) {
        customCategories.removeAll { $0.id == category.id }
        saveToStorage()
    }
    
    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    // MARK: - Accounts

    func addAccount(name: String, balance: Double, currency: String) {
        let account = Account(name: name, balance: balance, currency: currency)
        accounts.append(account)
        saveToStorage()
    }

    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    func deleteAccount(_ account: Account) {
        // Удаляем все операции, связанные с этим счетом
        allTransactions.removeAll { transaction in
            transaction.accountId == account.id || transaction.targetAccountId == account.id
        }
        
        accounts.removeAll { $0.id == account.id }
        recalculateAccountBalances()
        saveToStorage()
    }

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }

        let currency = accounts[sourceIndex].currency

        // Обновляем балансы
        accounts[sourceIndex].balance -= amount
        accounts[targetIndex].balance += amount

        // Сохраняем как internalTransfer-транзакцию
        let id = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .internalTransfer,
            currency: currency
        )

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            type: .internalTransfer,
            category: "Transfer",
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId
        )

        allTransactions.append(transferTx)
        allTransactions.sort { $0.date > $1.date }
        saveToStorage()
    }
    
    private func applyRules(to transactions: [Transaction]) -> [Transaction] {
        guard !categoryRules.isEmpty else { return transactions }
        
        let rulesMap = Dictionary(
            uniqueKeysWithValues: categoryRules.map { ($0.description.lowercased(), $0) }
        )
        
        return transactions.map { transaction in
            if let rule = rulesMap[transaction.description.lowercased()] {
                return Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    type: transaction.type,
                    category: rule.category,
                    subcategory: rule.subcategory
                )
            }
            return transaction
        }
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(allTransactions) {
            UserDefaults.standard.set(encoded, forKey: storageKeyTransactions)
        }
        if let encoded = try? JSONEncoder().encode(categoryRules) {
            UserDefaults.standard.set(encoded, forKey: storageKeyRules)
        }
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: storageKeyAccounts)
        }
        if let encoded = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(encoded, forKey: storageKeyCustomCategories)
        }
    }
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKeyTransactions),
           let decoded = try? JSONDecoder().decode([Transaction].self, from: data) {
            allTransactions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyRules),
           let decoded = try? JSONDecoder().decode([CategoryRule].self, from: data) {
            categoryRules = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyAccounts),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyCustomCategories),
           let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            customCategories = decoded
        }
        recalculateAccountBalances()
    }

    private func recalculateAccountBalances() {
        guard !accounts.isEmpty else { return }

        var balancesById: [String: Double] = [:]
        for account in accounts {
            balancesById[account.id] = 0
        }

        for tx in allTransactions {
            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    balancesById[accountId, default: 0] += tx.amount
                }
            case .expense:
                if let accountId = tx.accountId {
                    balancesById[accountId, default: 0] -= tx.amount
                }
            case .internalTransfer:
                if let sourceId = tx.accountId {
                    balancesById[sourceId, default: 0] -= tx.amount
                }
                if let targetId = tx.targetAccountId {
                    balancesById[targetId, default: 0] += tx.amount
                }
            }
        }

        for index in accounts.indices {
            if let newBalance = balancesById[accounts[index].id] {
                accounts[index].balance = newBalance
            }
        }
    }
}

struct DateFilter {
    var startDate: Date?
    var endDate: Date?
}

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
