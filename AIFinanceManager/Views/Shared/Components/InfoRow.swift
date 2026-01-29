//
//  InfoRow.swift
//  AIFinanceManager
//
//  Reusable info row component (label: value)
//

import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(AppTypography.body)
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.md) {
        InfoRow(label: "Категория", value: "Food")
        InfoRow(label: "Частота", value: "Ежемесячно")
        InfoRow(label: "Следующее списание", value: "15 января 2026")
    }
    .padding()
}
