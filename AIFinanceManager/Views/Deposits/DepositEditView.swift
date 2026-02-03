//
//  DepositEditView.swift
//  AIFinanceManager
//
//  View for creating and editing deposits
//

import SwiftUI

struct DepositEditView: View {
    @ObservedObject var depositsViewModel: DepositsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalBalanceText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedBankLogo: BankLogo = .none
    @State private var interestRateText: String = ""
    @State private var interestPostingDay: Int = 1
    @State private var capitalizationEnabled: Bool = true
    @State private var showingBankLogoPicker = false
    @FocusState private var isNameFocused: Bool
    
    private let depositCurrencies = ["KZT", "USD", "EUR"]
    
    var body: some View {
        EditSheetContainer(
            title: account == nil ? String(localized: "deposit.new") : String(localized: "deposit.editTitle"),
            isSaveDisabled: name.isEmpty || bankName.isEmpty || principalBalanceText.isEmpty || interestRateText.isEmpty,
            onSave: {
                guard let principalBalance = AmountFormatter.parse(principalBalanceText),
                      let interestRate = AmountFormatter.parse(interestRateText) else {
                    return
                }

                let depositInfo = DepositInfo(
                    bankName: bankName,
                    principalBalance: principalBalance,
                    capitalizationEnabled: capitalizationEnabled,
                    interestRateAnnual: interestRate,
                    interestPostingDay: interestPostingDay
                )

                let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
                let newAccount = Account(
                    id: account?.id ?? UUID().uuidString,
                    name: name,
                    currency: currency,
                    bankLogo: selectedBankLogo,
                    depositInfo: depositInfo,
                    shouldCalculateFromTransactions: false,
                    initialBalance: balance
                )
                HapticManager.success()
                onSave(newAccount)
            },
            onCancel: onCancel
        ) {
            Section(header: Text(String(localized: "deposit.name"))) {
                TextField(String(localized: "deposit.namePlaceholder"), text: $name)
                    .focused($isNameFocused)
            }

            Section(header: Text(String(localized: "deposit.bank"))) {
                TextField(String(localized: "deposit.bankNamePlaceholder"), text: $bankName)

                Button(action: {
                    HapticManager.selection()
                    showingBankLogoPicker = true
                }) {
                    HStack {
                        Text(String(localized: "deposit.selectLogo"))
                        Spacer()
                        selectedBankLogo.image(size: AppIconSize.lg)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(AppTypography.caption)
                    }
                }
            }

            Section(header: Text(String(localized: "common.currency"))) {
                Picker(String(localized: "common.currency"), selection: $currency) {
                    ForEach(depositCurrencies, id: \.self) { curr in
                        Text("\(Formatting.currencySymbol(for: curr)) \(curr)").tag(curr)
                    }
                }
            }

            Section(header: Text(String(localized: "deposit.initialAmount"))) {
                TextField(String(localized: "common.balancePlaceholder"), text: $principalBalanceText)
                    .keyboardType(.decimalPad)
            }

            Section(header: Text(String(localized: "deposit.interestRate"))) {
                HStack {
                    TextField("0.0", text: $interestRateText)
                        .keyboardType(.decimalPad)
                    Text(String(localized: "deposit.rateAnnual"))
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text(String(localized: "deposit.postingDayTitle"))) {
                Picker(String(localized: "deposit.dayOfMonth"), selection: $interestPostingDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Text(String(localized: "deposit.postingDayHint"))
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(String(localized: "deposit.capitalizationTitle"))) {
                Toggle(String(localized: "deposit.enableCapitalization"), isOn: $capitalizationEnabled)
                Text(String(localized: "deposit.capitalizationHint"))
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if let account = account, let depositInfo = account.depositInfo {
                name = account.name
                bankName = depositInfo.bankName
                principalBalanceText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue)
                currency = account.currency
                selectedBankLogo = account.bankLogo
                interestRateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
                interestPostingDay = depositInfo.interestPostingDay
                capitalizationEnabled = depositInfo.capitalizationEnabled
                isNameFocused = false
            } else {
                currency = "KZT"
                selectedBankLogo = .none
                principalBalanceText = ""
                interestRateText = ""
                interestPostingDay = 1
                capitalizationEnabled = true
                // Активируем поле названия при создании нового депозита
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                    isNameFocused = true
                }
            }
        }
        .sheet(isPresented: $showingBankLogoPicker) {
            BankLogoPickerView(selectedLogo: $selectedBankLogo)
        }
    }
}

// MARK: - Previews

#Preview("Deposit Edit View - New") {
    let coordinator = AppCoordinator()
    NavigationView {
        DepositEditView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            account: nil,
            onSave: { _ in },
            onCancel: {}
        )
    }
}

#Preview("Deposit Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "test",
        name: "Halyk Deposit",
        currency: "KZT",
        bankLogo: .halykBank,
        depositInfo: DepositInfo(
            bankName: "Halyk Bank",
            principalBalance: Decimal(1000000),
            capitalizationEnabled: true,
            interestRateAnnual: Decimal(12.5),
            interestPostingDay: 15
        ),
        initialBalance: 1000000
    )

    NavigationView {
        DepositEditView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            account: sampleAccount,
            onSave: { _ in },
            onCancel: {}
        )
    }
}
