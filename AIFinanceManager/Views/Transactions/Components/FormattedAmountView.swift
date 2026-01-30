//
//  FormattedAmountView.swift
//  AIFinanceManager
//
//  Created on 2026-01-30
//  Formatted amount display with separate opacity for decimal part
//

import SwiftUI

struct FormattedAmountView: View {
    let amount: Double
    let currency: String
    let prefix: String
    let color: Color

    private var formattedParts: (integer: String, decimal: String, symbol: String) {
        let symbol = Formatting.currencySymbol(for: currency)
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = " "
        numberFormatter.decimalSeparator = "."
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        let formatted = numberFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)

        // Разделяем на целую и дробную части
        let components = formatted.split(separator: ".")
        let integerPart = String(components.first ?? "0")
        let decimalPart = components.count > 1 ? String(components[1]) : "00"

        return (integerPart, decimalPart, symbol)
    }

    private var shouldShowDecimal: Bool {
        amount.truncatingRemainder(dividingBy: 1) != 0
    }

    var body: some View {
        let parts = formattedParts

        HStack(spacing: 0) {
            Text(prefix + parts.integer)
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(color)

            if shouldShowDecimal {
                Text("." + parts.decimal)
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                    .opacity(0.5)  // 50% прозрачности для дробной части
            }

            Text(" " + parts.symbol)
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        FormattedAmountView(amount: 1000.00, currency: "KZT", prefix: "+", color: .green)
        FormattedAmountView(amount: 1234.56, currency: "USD", prefix: "-", color: .primary)
        FormattedAmountView(amount: 500.50, currency: "EUR", prefix: "", color: .blue)
    }
    .padding()
}
