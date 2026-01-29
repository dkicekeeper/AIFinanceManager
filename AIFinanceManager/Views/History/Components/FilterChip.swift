//
//  FilterChip.swift
//  AIFinanceManager
//
//  Reusable filter chip component
//

import SwiftUI

struct FilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void
    
    init(title: String, icon: String? = nil, isSelected: Bool = false, onTap: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: AppIconSize.sm))
                }
                Text(title)
            }
            .filterChipStyle(isSelected: isSelected)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Filter Chips") {
    HStack(spacing: AppSpacing.md) {
        FilterChip(title: "All Accounts", icon: "calendar", onTap: {})
        FilterChip(title: "Selected", icon: "checkmark", isSelected: true, onTap: {})
    }
    .padding()
}
