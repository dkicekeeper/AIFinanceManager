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
    let showChevron: Bool
    let onTap: () -> Void

    init(
        title: String,
        icon: String? = nil,
        isSelected: Bool = false,
        showChevron: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.showChevron = showChevron
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: AppIconSize.sm))
            }
            Text(title)
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.xs))
            }
        }
        .filterChipStyle(isSelected: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Filter Chips") {
    HStack(spacing: AppSpacing.md) {
        FilterChip(title: "All Accounts", icon: "calendar", onTap: {})
        FilterChip(title: "Selected", icon: "checkmark", isSelected: true, onTap: {})
    }
    .padding()
}
