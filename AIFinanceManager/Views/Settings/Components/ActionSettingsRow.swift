//
//  ActionSettingsRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based action row for Settings
/// Single Responsibility: Display action button with icon, title, and optional destructive styling
struct ActionSettingsRow: View {
    // MARK: - Props

    let icon: String
    let title: String
    let iconColor: Color?
    let titleColor: Color?
    let isDestructive: Bool
    let action: () -> Void

    // MARK: - Initializer

    init(
        icon: String,
        title: String,
        iconColor: Color? = nil,
        titleColor: Color? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.titleColor = titleColor
        self.isDestructive = isDestructive
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppIconSize.md))
                    .foregroundColor(iconColor ?? (isDestructive ? AppColors.destructive : AppColors.accent))

                Text(title)
                    .font(AppTypography.body)
                    .foregroundColor(titleColor ?? (isDestructive ? AppColors.destructive : AppColors.textPrimary))
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        ActionSettingsRow(
            icon: "square.and.arrow.up",
            title: String(localized: "settings.exportData")
        ) {
            print("Export tapped")
        }

        ActionSettingsRow(
            icon: "square.and.arrow.down",
            title: String(localized: "settings.importData")
        ) {
            print("Import tapped")
        }

        ActionSettingsRow(
            icon: "arrow.triangle.2.circlepath",
            title: String(localized: "settings.recalculateBalances"),
            iconColor: AppColors.warning,
            titleColor: AppColors.warning
        ) {
            print("Recalculate tapped")
        }

        ActionSettingsRow(
            icon: "trash",
            title: String(localized: "settings.resetData"),
            isDestructive: true
        ) {
            print("Reset tapped")
        }
    }
}
