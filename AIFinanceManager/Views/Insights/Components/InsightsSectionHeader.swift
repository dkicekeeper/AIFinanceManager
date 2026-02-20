//
//  InsightsSectionHeader.swift
//  AIFinanceManager
//
//  Reusable section header for all Insights sections.
//  Displays InsightCategory icon (accent) and localised display name.
//

import SwiftUI

/// Standard section header for Insights sections.
/// Replaces the identical `private var sectionHeader` found in every section view.
struct InsightsSectionHeader: View {
    let category: InsightCategory

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: category.icon)
                .foregroundStyle(AppColors.accent)
            Text(category.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenPadding()
    }
}

// MARK: - Previews

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        InsightsSectionHeader(category: .spending)
        InsightsSectionHeader(category: .income)
        InsightsSectionHeader(category: .cashFlow)
        InsightsSectionHeader(category: .wealth)
    }
}
