//
//  InsightPreviewData.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Shared mock data used exclusively by #Preview blocks across Insights views.
//  Not shipped in production — all symbols are internal and preview-only.
//

import SwiftUI

// MARK: - Mock Monthly Trend

extension MonthlyDataPoint {
    static func mockTrend() -> [MonthlyDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let abbrev = DateFormatter()
        abbrev.dateFormat = "MMM"
        let id = DateFormatter()
        id.dateFormat = "yyyy-MM"

        let incomeValues:   [Double] = [420_000, 385_000, 510_000, 470_000, 495_000, 530_000]
        let expenseValues:  [Double] = [310_000, 340_000, 290_000, 360_000, 280_000, 320_000]

        return (0..<6).reversed().enumerated().compactMap { idx, offset -> MonthlyDataPoint? in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let inc = incomeValues[idx]
            let exp = expenseValues[idx]
            return MonthlyDataPoint(
                id: id.string(from: date),
                month: date,
                income: inc,
                expenses: exp,
                netFlow: inc - exp,
                label: abbrev.string(from: date)
            )
        }
    }
}

// MARK: - Mock Category Breakdown

extension CategoryBreakdownItem {
    static func mockItems() -> [CategoryBreakdownItem] {
        [
            CategoryBreakdownItem(id: "food",     categoryName: "Еда",         amount: 85_000, percentage: 32, color: .orange,  iconSource: .sfSymbol("fork.knife"),         subcategories: []),
            CategoryBreakdownItem(id: "transport",categoryName: "Транспорт",   amount: 52_000, percentage: 20, color: .blue,    iconSource: .sfSymbol("car.fill"),            subcategories: []),
            CategoryBreakdownItem(id: "shopping", categoryName: "Покупки",     amount: 43_000, percentage: 16, color: .pink,    iconSource: .sfSymbol("bag.fill"),            subcategories: []),
            CategoryBreakdownItem(id: "health",   categoryName: "Здоровье",    amount: 35_000, percentage: 13, color: .green,   iconSource: .sfSymbol("heart.fill"),          subcategories: []),
            CategoryBreakdownItem(id: "other",    categoryName: "Другое",      amount: 50_000, percentage: 19, color: .gray,    iconSource: .sfSymbol("ellipsis.circle.fill"), subcategories: [])
        ]
    }
}

// MARK: - Mock Budget Items

extension BudgetInsightItem {
    static func mockItems() -> [BudgetInsightItem] {
        [
            BudgetInsightItem(id: "food",     categoryName: "Еда",       budgetAmount: 80_000,  spent: 85_000,  percentage: 106, isOverBudget: true,  color: .orange, daysRemaining: 0,  projectedSpend: 85_000,  iconSource: .sfSymbol("fork.knife")),
            BudgetInsightItem(id: "shopping", categoryName: "Покупки",   budgetAmount: 60_000,  spent: 43_000,  percentage: 72,  isOverBudget: false, color: .pink,   daysRemaining: 8,  projectedSpend: 58_000,  iconSource: .sfSymbol("bag.fill")),
            BudgetInsightItem(id: "health",   categoryName: "Здоровье",  budgetAmount: 50_000,  spent: 35_000,  percentage: 70,  isOverBudget: false, color: .green,  daysRemaining: 8,  projectedSpend: 44_000,  iconSource: .sfSymbol("heart.fill"))
        ]
    }
}

// MARK: - Mock Recurring Items

extension RecurringInsightItem {
    static func mockItems() -> [RecurringInsightItem] {
        [
            RecurringInsightItem(id: "netflix",  name: "Netflix",     amount: 4_990,   currency: "KZT", frequency: .monthly, kind: .subscription, status: .active, iconSource: .sfSymbol("play.rectangle.fill"),    monthlyEquivalent: 4_990),
            RecurringInsightItem(id: "spotify",  name: "Spotify",     amount: 1_990,   currency: "KZT", frequency: .monthly, kind: .subscription, status: .active, iconSource: .sfSymbol("music.note"),             monthlyEquivalent: 1_990),
            RecurringInsightItem(id: "gym",      name: "Фитнес зал",  amount: 15_000,  currency: "KZT", frequency: .monthly, kind: .generic,      status: .active, iconSource: .sfSymbol("dumbbell.fill"),          monthlyEquivalent: 15_000),
            RecurringInsightItem(id: "salary",   name: "Зарплата",    amount: 450_000, currency: "KZT", frequency: .monthly, kind: .generic,      status: .active, iconSource: .sfSymbol("dollarsign.circle.fill"), monthlyEquivalent: 450_000)
        ]
    }
}

// MARK: - Mock Insights

extension Insight {
    // Spending — top category with chart
    static func mockTopSpending() -> Insight {
        Insight(
            id: "preview_top",
            type: .topSpendingCategory,
            title: "Топ категория",
            subtitle: "Еда",
            metric: InsightMetric(value: 85_000, formattedValue: "85 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .down, changePercent: 32, changeAbsolute: nil, comparisonPeriod: "32% от общих"),
            severity: .warning,
            category: .spending,
            detailData: .categoryBreakdown(CategoryBreakdownItem.mockItems())
        )
    }

    // Month-over-month — no chart
    static func mockMoM() -> Insight {
        Insight(
            id: "preview_mom",
            type: .monthOverMonthChange,
            title: "Месяц к месяцу",
            subtitle: "Расходы",
            metric: InsightMetric(value: 320_000, formattedValue: "320 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 14.3, changeAbsolute: 40_000, comparisonPeriod: "vs прошлый месяц"),
            severity: .warning,
            category: .spending,
            detailData: nil
        )
    }

    // Average daily — no chart
    static func mockAvgDaily() -> Insight {
        Insight(
            id: "preview_avg",
            type: .averageDailySpending,
            title: "Средний день",
            subtitle: "31 день",
            metric: InsightMetric(value: 10_323, formattedValue: "10 323 ₸", currency: "KZT", unit: nil),
            trend: nil,
            severity: .neutral,
            category: .spending,
            detailData: nil
        )
    }

    // Income growth
    static func mockIncomeGrowth() -> Insight {
        Insight(
            id: "preview_income",
            type: .incomeGrowth,
            title: "Рост доходов",
            subtitle: "vs прошлый месяц",
            metric: InsightMetric(value: 530_000, formattedValue: "530 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 7.1, changeAbsolute: 35_000, comparisonPeriod: "vs прошлый месяц"),
            severity: .positive,
            category: .income,
            detailData: nil
        )
    }

    // Budget overspend
    static func mockBudgetOver() -> Insight {
        Insight(
            id: "preview_budget",
            type: .budgetOverspend,
            title: "Превышен бюджет",
            subtitle: "1 категория",
            metric: InsightMetric(value: 1, formattedValue: "1", currency: nil, unit: "категория"),
            trend: nil,
            severity: .critical,
            category: .budget,
            detailData: .budgetProgressList(BudgetInsightItem.mockItems())
        )
    }

    // Recurring total
    static func mockRecurring() -> Insight {
        Insight(
            id: "preview_recurring",
            type: .totalRecurringCost,
            title: "Регулярные платежи",
            subtitle: "3 активных",
            metric: InsightMetric(value: 21_980, formattedValue: "21 980 ₸", currency: "KZT", unit: "/ мес"),
            trend: nil,
            severity: .neutral,
            category: .recurring,
            detailData: .recurringList(RecurringInsightItem.mockItems())
        )
    }

    // Cash flow
    static func mockCashFlow() -> Insight {
        let trend = MonthlyDataPoint.mockTrend()
        return Insight(
            id: "preview_cashflow",
            type: .netCashFlow,
            title: "Чистый поток",
            subtitle: trend.last?.label ?? "Июнь",
            metric: InsightMetric(value: 210_000, formattedValue: "210 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: nil, changeAbsolute: 30_000, comparisonPeriod: "vs среднее"),
            severity: .positive,
            category: .cashFlow,
            detailData: .monthlyTrend(trend)
        )
    }

    // Projected balance
    static func mockProjectedBalance() -> Insight {
        Insight(
            id: "preview_balance",
            type: .projectedBalance,
            title: "Прогноз баланса",
            subtitle: "Через 30 дней",
            metric: InsightMetric(value: 1_250_000, formattedValue: "1 250 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: nil, changeAbsolute: 21_980, comparisonPeriod: "+21 980 ₸ прогноз"),
            severity: .positive,
            category: .cashFlow,
            detailData: nil
        )
    }
}
