//
//  CategoryDisplayData.swift
//  AIFinanceManager
//
//  Unified model for displaying category in grid/list.
//  Single source of truth for category presentation.
//

import Foundation
import SwiftUI
import Combine

/// Display data for a category in UI
struct CategoryDisplayData: Identifiable, Hashable {
    let id: String
    let name: String
    let type: TransactionType
    let iconName: String
    let iconColor: Color
    let total: Double
    let budgetAmount: Double?
    let budgetProgress: BudgetProgress?

    // MARK: - Convenience Properties

    /// Whether category has any transactions
    var hasTotal: Bool { total != 0 }

    /// Whether category has a budget set
    var hasBudget: Bool { budgetAmount != nil }

    /// Formatted total for display
    func formattedTotal(currency: String) -> String? {
        guard hasTotal else { return nil }
        return Formatting.formatCurrency(total, currency: currency)
    }

    /// Formatted budget for display
    func formattedBudget(currency: String) -> String? {
        guard let budget = budgetAmount else { return nil }
        return Formatting.formatCurrency(budget, currency: currency)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
