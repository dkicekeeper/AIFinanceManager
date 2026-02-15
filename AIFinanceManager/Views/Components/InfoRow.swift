//
//  InfoRow.swift
//  AIFinanceManager
//
//  Reusable info row component (label: value)
//

import SwiftUI

struct InfoRow: View {
    let icon: String?
    let label: String
    let value: String

    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: AppIconSize.md)
            }
            Text(label)
                .font(AppTypography.bodyLarge)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AppTypography.bodyLarge)
        }
        .padding(.vertical, AppSpacing.compact)
    }
}

#Preview {
    VStack() {
        InfoRow(icon: "tag.fill", label: "Категория", value: "Food")
        InfoRow(icon: "calendar", label: "Частота", value: "Ежемесячно")
        InfoRow(icon: "clock.fill", label: "Следующее списание", value: "15 января 2026")
        InfoRow(label: "Без иконки", value: "Значение")
    }
    .padding()
}
