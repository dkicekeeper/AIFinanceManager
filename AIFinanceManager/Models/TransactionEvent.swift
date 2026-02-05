//
//  TransactionEvent.swift
//  AIFinanceManager
//
//  Created on 2026-02-05
//  Refactoring Phase 0: Event Sourcing Model
//

import Foundation

/// Event representing a transaction state change
/// Used for event sourcing pattern - all transaction modifications go through events
enum TransactionEvent {
    case added(Transaction)
    case updated(old: Transaction, new: Transaction)
    case deleted(Transaction)
    case bulkAdded([Transaction])

    // MARK: - Computed Properties

    /// Account IDs affected by this event
    /// Used to determine which account balances need recalculation
    var affectedAccounts: Set<String> {
        switch self {
        case .added(let tx):
            return accountIds(from: tx)

        case .updated(let old, let new):
            var ids = accountIds(from: old)
            ids.formUnion(accountIds(from: new))
            return ids

        case .deleted(let tx):
            return accountIds(from: tx)

        case .bulkAdded(let transactions):
            return Set(transactions.flatMap { accountIds(from: $0) })
        }
    }

    /// Category names affected by this event
    /// Used to determine which category aggregates need recalculation
    var affectedCategories: Set<String> {
        switch self {
        case .added(let tx):
            return Set([tx.category].compactMap { $0.isEmpty ? nil : $0 })

        case .updated(let old, let new):
            var categories = Set<String>()
            if !old.category.isEmpty {
                categories.insert(old.category)
            }
            if !new.category.isEmpty {
                categories.insert(new.category)
            }
            return categories

        case .deleted(let tx):
            return Set([tx.category].compactMap { $0.isEmpty ? nil : $0 })

        case .bulkAdded(let transactions):
            return Set(transactions.map { $0.category }.filter { !$0.isEmpty })
        }
    }

    /// All transactions involved in this event
    var transactions: [Transaction] {
        switch self {
        case .added(let tx):
            return [tx]
        case .updated(_, let new):
            return [new]
        case .deleted(let tx):
            return [tx]
        case .bulkAdded(let txs):
            return txs
        }
    }

    /// Human-readable description for debugging
    var debugDescription: String {
        switch self {
        case .added(let tx):
            return "ADD: \(tx.category) \(tx.amount) \(tx.currency)"
        case .updated(let old, let new):
            return "UPDATE: \(old.id) - \(old.amount) → \(new.amount)"
        case .deleted(let tx):
            return "DELETE: \(tx.category) \(tx.amount) \(tx.currency)"
        case .bulkAdded(let txs):
            return "BULK_ADD: \(txs.count) transactions"
        }
    }

    // MARK: - Private Helpers

    /// Extract all account IDs from a transaction
    private func accountIds(from transaction: Transaction) -> Set<String> {
        var ids = Set<String>()

        if let accountId = transaction.accountId, !accountId.isEmpty {
            ids.insert(accountId)
        }

        if let targetId = transaction.targetAccountId, !targetId.isEmpty {
            ids.insert(targetId)
        }

        return ids
    }
}

// MARK: - Equatable

extension TransactionEvent: Equatable {
    static func == (lhs: TransactionEvent, rhs: TransactionEvent) -> Bool {
        switch (lhs, rhs) {
        case (.added(let lhsTx), .added(let rhsTx)):
            return lhsTx.id == rhsTx.id

        case (.updated(let lhsOld, let lhsNew), .updated(let rhsOld, let rhsNew)):
            return lhsOld.id == rhsOld.id && lhsNew.id == rhsNew.id

        case (.deleted(let lhsTx), .deleted(let rhsTx)):
            return lhsTx.id == rhsTx.id

        case (.bulkAdded(let lhsTxs), .bulkAdded(let rhsTxs)):
            return lhsTxs.map { $0.id } == rhsTxs.map { $0.id }

        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension TransactionEvent: CustomStringConvertible {
    var description: String {
        debugDescription
    }
}
