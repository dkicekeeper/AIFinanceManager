//
//  InsightModels.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Data models for smart financial insights and analytics
//

import SwiftUI

// MARK: - Core Insight Model

/// Represents a single actionable financial insight
struct Insight: Identifiable {
    let id: String
    let type: InsightType
    let title: String
    let subtitle: String
    let metric: InsightMetric
    let trend: InsightTrend?
    let severity: InsightSeverity
    let category: InsightCategory
    let detailData: InsightDetailData?
}

// MARK: - Insight Type

enum InsightType: String {
    case topSpendingCategory
    case spendingSpike
    case monthOverMonthChange
    case averageDailySpending
    case incomeGrowth
    case incomeSourceBreakdown
    case incomeVsExpenseRatio
    case budgetOverspend
    case budgetUnderutilized
    case projectedOverspend
    case categoryTrend
    case subcategoryBreakdown
    case totalRecurringCost
    case subscriptionGrowth
    case netCashFlow
    case bestMonth
    case worstMonth
    case projectedBalance
    case accountActivity
    // Phase 18 — Wealth
    case totalWealth      // Current sum of all account balances
    case wealthGrowth     // Monthly/period growth of accumulated balance
}

// MARK: - Insight Metric

struct InsightMetric {
    let value: Double
    let formattedValue: String
    let currency: String?
    let unit: String?
}

// MARK: - Insight Trend

struct InsightTrend {
    let direction: TrendDirection
    let changePercent: Double?
    let changeAbsolute: Double?
    let comparisonPeriod: String

    var trendColor: Color {
        switch direction {
        case .up: return AppColors.income
        case .down: return AppColors.destructive
        case .flat: return AppColors.textSecondary
        }
    }

    var trendIcon: String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }
}

enum TrendDirection {
    case up, down, flat
}

// MARK: - Insight Severity

enum InsightSeverity: String {
    case positive
    case neutral
    case warning
    case critical

    var color: Color {
        switch self {
        case .positive: return AppColors.success
        case .neutral: return AppColors.accent
        case .warning: return AppColors.warning
        case .critical: return AppColors.destructive
        }
    }

    var icon: String {
        switch self {
        case .positive: return "checkmark.circle.fill"
        case .neutral: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Insight Category

enum InsightCategory: String, CaseIterable {
    case spending
    case income
    case budget
    case recurring
    case cashFlow
    case wealth     // Phase 18 — Accumulated capital card

    var displayName: String {
        switch self {
        case .spending: return String(localized: "insights.spending")
        case .income:   return String(localized: "insights.income")
        case .budget:   return String(localized: "insights.budget")
        case .recurring: return String(localized: "insights.recurring")
        case .cashFlow: return String(localized: "insights.cashFlow")
        case .wealth:   return String(localized: "insights.wealth")
        }
    }

    var icon: String {
        switch self {
        case .spending:  return "arrow.down.circle"
        case .income:    return "arrow.up.circle"
        case .budget:    return "gauge.with.dots.needle.33percent"
        case .recurring: return "repeat.circle"
        case .cashFlow:  return "chart.line.uptrend.xyaxis"
        case .wealth:    return "banknote"
        }
    }
}

// MARK: - Detail Data

enum InsightDetailData {
    case categoryBreakdown([CategoryBreakdownItem])
    case monthlyTrend([MonthlyDataPoint])
    case periodTrend([PeriodDataPoint])         // Phase 18 — granularity-aware trend
    case dailyTrend([DailyDataPoint])
    case budgetProgressList([BudgetInsightItem])
    case recurringList([RecurringInsightItem])
    case accountComparison([AccountInsightItem])
    case wealthBreakdown([AccountInsightItem])   // Phase 18 — per-account balances
}

// MARK: - Category Breakdown

struct CategoryBreakdownItem: Identifiable {
    let id: String
    let categoryName: String
    let amount: Double
    let percentage: Double
    let color: Color
    let iconSource: IconSource?
    let subcategories: [SubcategoryBreakdownItem]
}

struct SubcategoryBreakdownItem: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let percentage: Double
}

// MARK: - Trend Data Points

struct MonthlyDataPoint: Identifiable {
    let id: String
    let month: Date
    let income: Double
    let expenses: Double
    let netFlow: Double
    let label: String
}

struct DailyDataPoint: Identifiable {
    let id: String
    let date: Date
    let amount: Double
    let label: String
}

// MARK: - Budget Insight Item

struct BudgetInsightItem: Identifiable {
    let id: String
    let categoryName: String
    let budgetAmount: Double
    let spent: Double
    let percentage: Double
    let isOverBudget: Bool
    let color: Color
    let daysRemaining: Int
    let projectedSpend: Double
    let iconSource: IconSource?
}

// MARK: - Recurring Insight Item

struct RecurringInsightItem: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let currency: String
    let frequency: RecurringFrequency
    let kind: RecurringSeriesKind
    let status: SubscriptionStatus?
    let iconSource: IconSource?
    let monthlyEquivalent: Double
}

// MARK: - Account Insight Item

struct AccountInsightItem: Identifiable {
    let id: String
    let accountName: String
    let currency: String
    let balance: Double
    let transactionCount: Int
    let lastActivityDate: Date?
    let iconSource: IconSource?
}
