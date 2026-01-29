//
//  BankLogoRow.swift
//  AIFinanceManager
//
//  Reusable bank logo row component for bank selection
//

import SwiftUI

struct BankLogoRow: View {
    let bank: BankLogo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.selection()
            onSelect()
        }) {
            HStack(spacing: AppSpacing.md) {
                bank.image(size: AppIconSize.xl)
                    .frame(width: AppIconSize.xl, height: AppIconSize.xl)
                
                Text(bank.displayName)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
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
