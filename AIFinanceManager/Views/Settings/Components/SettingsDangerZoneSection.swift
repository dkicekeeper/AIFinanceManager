//
//  SettingsDangerZoneSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based Danger Zone section for Settings
/// Single Responsibility: Group dangerous actions (recalculate, reset)
struct SettingsDangerZoneSection: View {
    // MARK: - Props

    let onRecalculateBalances: () -> Void
    let onResetData: () -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.dangerZone"))) {
            ActionSettingsRow(
                icon: "arrow.triangle.2.circlepath",
                title: String(localized: "settings.recalculateBalances"),
                iconColor: AppColors.warning,
                titleColor: AppColors.warning,
                action: onRecalculateBalances
            )

            ActionSettingsRow(
                icon: "trash",
                title: String(localized: "settings.resetData"),
                isDestructive: true,
                action: onResetData
            )
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        SettingsDangerZoneSection(
            onRecalculateBalances: {
            },
            onResetData: {
            }
        )
    }
}
