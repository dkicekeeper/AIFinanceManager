//
//  ImportProgressSheet.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based import progress sheet for Settings
/// Single Responsibility: Display import progress with cancellation
struct ImportProgressSheet: View {
    // MARK: - Props

    let currentRow: Int
    let totalRows: Int
    let progress: Double
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Text(String(localized: "progress.importing"))
                .font(AppTypography.h4)
                .foregroundColor(AppColors.textPrimary)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppColors.accent)

            Text("\(currentRow) / \(totalRows)")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            Button(String(localized: "button.cancel")) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .tint(AppColors.destructive)
        }
        .padding(AppSpacing.xxl)
        .interactiveDismissDisabled()
    }
}

// MARK: - Preview

#Preview {
    ImportProgressSheet(
        currentRow: 42,
        totalRows: 100,
        progress: 0.42,
        onCancel: {
            print("Cancel tapped")
        }
    )
}
