//
//  BankLogoPickerView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct BankLogoPickerView: View {
    @Binding var selectedLogo: BankLogo
    @Environment(\.dismiss) var dismiss

    // Группируем банки по категориям для удобства
    private var popularBanks: [BankLogo] {
        [.alatauCityBank, .halykBank, .kaspi, .homeCredit, .eurasian, .forte, .jusan]
    }

    private var otherBanks: [BankLogo] {
        BankLogo.allCases.filter { $0 != .none && !popularBanks.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(String(localized: "account.popularBanks"))) {
                    ForEach(popularBanks) { bank in
                        BankLogoRow(
                            bank: bank,
                            isSelected: selectedLogo == bank,
                            onSelect: {
                                selectedLogo = bank
                                dismiss()
                            }
                        )
                    }
                }

                Section(header: Text(String(localized: "account.otherBanks"))) {
                    ForEach(otherBanks) { bank in
                        BankLogoRow(
                            bank: bank,
                            isSelected: selectedLogo == bank,
                            onSelect: {
                                selectedLogo = bank
                                dismiss()
                            }
                        )
                    }
                }

                Section {
                    BankLogoRow(
                        bank: .none,
                        isSelected: selectedLogo == .none,
                        onSelect: {
                            selectedLogo = .none
                            dismiss()
                        }
                    )
                }
            }
            .navigationTitle(String(localized: "navigation.selectLogo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Bank Logo Picker") {
    @Previewable @State var selectedLogo: BankLogo = .kaspi

    return BankLogoPickerView(selectedLogo: $selectedLogo)
}
