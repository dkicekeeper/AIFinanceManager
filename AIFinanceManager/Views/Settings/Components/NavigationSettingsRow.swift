//
//  NavigationSettingsRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based navigation row for Settings
/// Single Responsibility: Display navigation link with icon and title
struct NavigationSettingsRow<Destination: View>: View {
    // MARK: - Props

    let icon: String
    let title: String
    let iconColor: Color
    let destination: Destination

    // MARK: - Initializer

    init(
        icon: String,
        title: String,
        iconColor: Color = AppColors.accent,
        @ViewBuilder destination: () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = destination()
    }

    // MARK: - Body

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppIconSize.md))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            NavigationSettingsRow(
                icon: "tag",
                title: String(localized: "settings.categories")
            ) {
                Text("Categories Management")
            }

            NavigationSettingsRow(
                icon: "creditcard",
                title: String(localized: "settings.accounts")
            ) {
                Text("Accounts Management")
            }
        }
    }
}
