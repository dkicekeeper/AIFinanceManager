//
//  BankLogoRow.swift
//  AIFinanceManager
//
//  Reusable bank logo row component for bank selection
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Bank logo selection row with checkmark indicator
/// Now built on top of UniversalRow for consistency
struct BankLogoRow: View {
    let bank: BankLogo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        UniversalRow(
            config: .selectable,
            leadingIcon: .bankLogo(bank)
        ) {
            Text(bank.displayName)
                .foregroundStyle(AppColors.textPrimary)
        } trailing: {
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(AppColors.accent)
            }
        }
        .actionRow {
            HapticManager.selection()
            onSelect()
        }
    }
}

#Preview {
    List {
        BankLogoRow(
            bank: .kaspi,
            isSelected: true,
            onSelect: {}
        )
        
        BankLogoRow(
            bank: .halykBank,
            isSelected: false,
            onSelect: {}
        )
        
        BankLogoRow(
            bank: .none,
            isSelected: false,
            onSelect: {}
        )
    }
}
