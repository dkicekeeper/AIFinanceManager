//
//  DepositTransferView.swift
//  AIFinanceManager
//
//  Reusable deposit transfer component
//

import SwiftUI

enum DepositTransferDirection {
    case toDeposit  // Перевод на депозит (пополнение)
    case fromDeposit // Перевод с депозита (снятие)
}

struct DepositTransferView: View {
    let accounts: [Account]
    let depositAccount: Account
    let transferDirection: DepositTransferDirection
    let onTransferSaved: (String, String, Double, String, String) -> Void // (fromId, toId, amount, date, description)
    let onComplete: () -> Void
    @ObservedObject var balanceCoordinator: BalanceCoordinator

    @State private var selectedSourceAccountId: String? = nil
    @State private var amountText: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isAmountFocused: Bool

    private var availableAccounts: [Account] {
        accounts.filter { $0.id != depositAccount.id }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(transferDirection == .toDeposit ? String(localized: "deposit.sourceAccount") : String(localized: "deposit.targetAccount"))) {
                    if availableAccounts.isEmpty {
                        Text(String(localized: "deposit.noOtherAccounts"))
                            .foregroundColor(.secondary)
                            .font(AppTypography.caption)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.md) {
                                ForEach(availableAccounts) { sourceAccount in
                                    AccountRadioButton(
                                        account: sourceAccount,
                                        isSelected: selectedSourceAccountId == sourceAccount.id,
                                        onTap: {
                                            HapticManager.selection()
                                            selectedSourceAccountId = sourceAccount.id
                                        },
                                        balanceCoordinator: balanceCoordinator
                                    )
                                }
                            }
                            .padding(.vertical, AppSpacing.xs)
                        }
                    }
                }
                
                Section(header: Text(String(localized: "deposit.amount"))) {
                    TextField(String(localized: "common.balancePlaceholder"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                }
                
                Section(header: Text(String(localized: "deposit.description"))) {
                    TextField(String(localized: "deposit.descriptionOptional"), text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section(header: Text(String(localized: "deposit.date"))) {
                    DatePicker(String(localized: "deposit.date"), selection: $selectedDate, displayedComponents: .date)
                }
            }
            .navigationTitle(transferDirection == .toDeposit ? String(localized: "deposit.topUpTitle") : String(localized: "deposit.transferFromTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "button.cancel")) {
                        HapticManager.light()
                        onComplete()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.save")) {
                        HapticManager.success()
                        saveTransfer()
                    }
                    .disabled(amountText.isEmpty || selectedSourceAccountId == nil)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                isAmountFocused = true
            }
            .onAppear {
                descriptionText = transferDirection == .toDeposit ? String(localized: "deposit.topUpDescription") : String(localized: "deposit.transferFromDescription")
            }
            .alert(String(localized: "common.error"), isPresented: $showingError) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveTransfer() {
        guard let sourceAccountId = selectedSourceAccountId,
              let amount = AmountFormatter.parse(amountText) else {
            return
        }

        let dateString = DateFormatters.dateFormatter.string(from: selectedDate)
        let description = descriptionText.isEmpty
            ? (transferDirection == .toDeposit ? String(localized: "deposit.topUpDescription") : String(localized: "deposit.transferFromDescription"))
            : descriptionText

        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue

        if transferDirection == .toDeposit {
            // Перевод на депозит (с выбранного счета на депозит)
            onTransferSaved(sourceAccountId, depositAccount.id, amountDouble, dateString, description)
        } else {
            // Перевод с депозита (с депозита на выбранный счет)
            onTransferSaved(depositAccount.id, sourceAccountId, amountDouble, dateString, description)
        }

        onComplete()
    }
}

#Preview("Deposit Transfer - Top Up") {
    let coordinator = AppCoordinator()

    return DepositTransferView(
        accounts: [],
        depositAccount: Account(id: "test", name: "Test Deposit", currency: "KZT", bankLogo: .kaspi, initialBalance: 100000),
        transferDirection: .toDeposit,
        onTransferSaved: { from, to, amount, date, desc in
        },
        onComplete: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
}

#Preview("Deposit Transfer - Transfer From") {
    let coordinator = AppCoordinator()

    return DepositTransferView(
        accounts: [],
        depositAccount: Account(id: "test", name: "Test Deposit", currency: "KZT", bankLogo: .kaspi, initialBalance: 100000),
        transferDirection: .fromDeposit,
        onTransferSaved: { from, to, amount, date, desc in
        },
        onComplete: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
}
