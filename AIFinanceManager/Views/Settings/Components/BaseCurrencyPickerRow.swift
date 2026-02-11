//
//  BaseCurrencyPickerRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based currency picker row for Settings
/// Single Responsibility: Display and handle base currency selection
struct BaseCurrencyPickerRow: View {
    // MARK: - Props

    let selectedCurrency: String
    let availableCurrencies: [String]
    let onChange: (String) -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(AppColors.accent)

            Text(String(localized: "settings.baseCurrency"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Picker("", selection: Binding(
                get: { selectedCurrency },
                set: { onChange($0) }
            )) {
                ForEach(availableCurrencies, id: \.self) { currency in
                    Text(Formatting.currencySymbol(for: currency))
                        .tag(currency)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Preview

#Preview {
    List {
        BaseCurrencyPickerRow(
            selectedCurrency: "KZT",
            availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
            onChange: { newCurrency in
                print("Selected: \(newCurrency)")
            }
        )
    }
}
