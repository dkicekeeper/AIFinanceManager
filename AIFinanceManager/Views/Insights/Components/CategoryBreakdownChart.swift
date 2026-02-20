//
//  CategoryBreakdownChart.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Donut chart for category spending breakdown
//

import SwiftUI
import Charts

struct CategoryBreakdownChart: View {
    let items: [CategoryBreakdownItem]
    var compact: Bool = false

    private var displayItems: [CategoryBreakdownItem] {
        // Show top 5, group rest as "Other"
        if items.count <= 6 { return items }
        let top5 = Array(items.prefix(5))
        let otherTotal = items.dropFirst(5).reduce(0.0) { $0 + $1.amount }
        let otherPercent = items.dropFirst(5).reduce(0.0) { $0 + $1.percentage }
        let other = CategoryBreakdownItem(
            id: "other",
            categoryName: String(localized: "insights.other"),
            amount: otherTotal,
            percentage: otherPercent,
            color: AppColors.textTertiary,
            iconSource: nil,
            subcategories: []
        )
        return top5 + [other]
    }

    var body: some View {
        if compact {
            compactChart
        } else {
            fullChart
        }
    }

    private var compactChart: some View {
        Chart(displayItems, id: \.id) { item in
            SectorMark(
                angle: .value("Amount", item.amount),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .foregroundStyle(item.color)
        }
        .frame(height: 60)
        .chartLegend(.hidden)
    }

    private var fullChart: some View {
        VStack(spacing: AppSpacing.lg) {
            Chart(displayItems, id: \.id) { item in
                SectorMark(
                    angle: .value("Amount", item.amount),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
//                .lineCap(.round)
                .foregroundStyle(item.color)
                .annotation(position: .overlay) {
                    if item.percentage > 10 {
                        Text(String(format: "%.0f%%", item.percentage))
                            .font(AppTypography.captionEmphasis)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 240)
            .chartLegend(.hidden)

            // Custom legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                ForEach(displayItems, id: \.id) { item in
                    HStack(spacing: AppSpacing.xs) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.categoryName)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", item.percentage))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Full donut chart") {
    CategoryBreakdownChart(items: CategoryBreakdownItem.mockItems())
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (card mini-chart)") {
    VStack {
        CategoryBreakdownChart(items: CategoryBreakdownItem.mockItems(), compact: true)
            .screenPadding()
    }
    .frame(height: 100)
}
