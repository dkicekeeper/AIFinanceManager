//
//  CurrencySelectorView.swift
//  AIFinanceManager
//
//  Currency selector using Menu picker style
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
        Menu {
            ForEach(availableCurrencies, id: \.self) { currency in
                Button(action: {
                    selectedCurrency = currency
                    HapticManager.selection()
                }) {
                    HStack {
                        Text(Formatting.currencySymbol(for: currency))
                        Spacer()
                        if selectedCurrency == currency {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(Formatting.currencySymbol(for: selectedCurrency))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle()
        }
    }
}

#Preview("Currency Selector") {
    @Previewable @State var selectedCurrency = "KZT"
    
    return CurrencySelectorView(selectedCurrency: $selectedCurrency)
        .padding()
}
