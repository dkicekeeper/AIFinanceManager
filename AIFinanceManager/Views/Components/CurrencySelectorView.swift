//
//  CurrencySelectorView.swift
//  AIFinanceManager
//
//  Currency selector using FilterChip components
//

import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let availableCurrencies: [String]
    
    init(
        selectedCurrency: Binding<String>,
        availableCurrencies: [String] = ["KZT", "USD", "EUR", "RUB", "GBP"]
    ) {
        self._selectedCurrency = selectedCurrency
        self.availableCurrencies = availableCurrencies
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(availableCurrencies, id: \.self) { currency in
                    FilterChip(
                        title: Formatting.currencySymbol(for: currency),
                        isSelected: selectedCurrency == currency,
                        onTap: {
                            selectedCurrency = currency
                            HapticManager.selection()
                        }
                    )
                }
            }
//            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

#Preview("Currency Selector") {
    @Previewable @State var selectedCurrency = "KZT"
    
    return CurrencySelectorView(selectedCurrency: $selectedCurrency)
        .padding()
}
