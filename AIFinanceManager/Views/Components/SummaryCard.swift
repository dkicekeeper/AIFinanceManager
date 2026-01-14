//
//  SummaryCard.swift
//  AIFinanceManager
//
//  Reusable summary card component
//

import SwiftUI

struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(Formatting.formatCurrency(amount, currency: currency))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    VStack(spacing: AppSpacing.md) {
        SummaryCard(title: "Доходы", amount: 10000, currency: "KZT", color: .green)
        SummaryCard(title: "Расходы", amount: 5000, currency: "KZT", color: .red)
        SummaryCard(title: "Баланс", amount: 5000, currency: "KZT", color: .blue)
    }
    .padding()
}
