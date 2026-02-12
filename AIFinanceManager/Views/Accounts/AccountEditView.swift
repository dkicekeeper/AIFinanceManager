//
//  AccountEditView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountEditView: View {
    let accountsViewModel: AccountsViewModel
    let transactionsViewModel: TransactionsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var balanceText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedIconSource: IconSource? = nil
    @State private var showingIconPicker = false
    @FocusState private var isNameFocused: Bool

    private let currencies = ["USD", "EUR", "KZT", "RUB", "GBP"]

    private var parsedBalance: Double {
        if balanceText.isEmpty { return 0.0 }
        return Double(balanceText.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }

    var body: some View {
        EditSheetContainer(
            title: account == nil ? String(localized: "modal.newAccount") : String(localized: "modal.editAccount"),
            isSaveDisabled: name.isEmpty,
            onSave: {
                let newAccount = Account(
                    id: account?.id ?? UUID().uuidString,
                    name: name,
                    currency: currency,
                    iconSource: selectedIconSource,
                    shouldCalculateFromTransactions: false,
                    initialBalance: parsedBalance
                )
                onSave(newAccount)
            },
            onCancel: onCancel
        ) {
            Section(header: Text(String(localized: "common.name"))) {
                TextField(String(localized: "account.namePlaceholder"), text: $name)
                    .focused($isNameFocused)
            }

            Section(header: Text(String(localized: "common.logo"))) {
                Button {
                    HapticManager.light()
                    showingIconPicker = true
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Text(String(localized: "iconPicker.title"))
                        Spacer()
                        IconView(
                            source: selectedIconSource,
                            size: AppIconSize.lg
                        )
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }

            Section(header: Text(String(localized: "common.balance"))) {
                HStack {
                    TextField(String(localized: "common.balancePlaceholder"), text: $balanceText)
                        .keyboardType(.decimalPad)

                    Picker(String(localized: "common.currency"), selection: $currency) {
                        ForEach(currencies, id: \.self) { curr in
                            Text(Formatting.currencySymbol(for: curr)).tag(curr)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
        }
        .onAppear {
            if let account = account {
                name = account.name
                // Используем initialBalance для редактирования (для manual счетов)
                let balanceValue = account.initialBalance ?? 0
                balanceText = String(format: "%.2f", balanceValue)
                currency = account.currency
                selectedIconSource = account.iconSource
                isNameFocused = false
            } else {
                currency = transactionsViewModel.appSettings.baseCurrency
                selectedIconSource = nil
                balanceText = ""
                // Активируем поле названия при создании нового счета
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                    isNameFocused = true
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $selectedIconSource)
        }
    }
}

#Preview("Account Edit View - New") {
    let coordinator = AppCoordinator()

    AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Account Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "preview",
        name: "Test Account",
        currency: "USD",
        iconSource: .bankLogo(.kaspi),
        initialBalance: 10000
    )

    AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: sampleAccount,
        onSave: { _ in },
        onCancel: {}
    )
}
