//
//  DepositRateChangeView.swift
//  AIFinanceManager
//
//  Reusable deposit rate change component
//

import SwiftUI

struct DepositRateChangeView: View {
    @ObservedObject var depositsViewModel: DepositsViewModel
    let account: Account
    let onComplete: () -> Void
    
    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""
    @FocusState private var isRateFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(String(localized: "deposit.newRate"))) {
                    HStack {
                        TextField("0.0", text: $rateText)
                            .keyboardType(.decimalPad)
                            .focused($isRateFocused)
                        Text(String(localized: "deposit.rateAnnual"))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text(String(localized: "deposit.effectiveDate"))) {
                    DatePicker(String(localized: "deposit.date"), selection: $effectiveFromDate, displayedComponents: .date)
                }
                
                Section(header: Text(String(localized: "deposit.note"))) {
                    TextField(String(localized: "deposit.note"), text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: "deposit.changeRateTitle"))
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
                        saveRateChange()
                    }
                    .disabled(rateText.isEmpty)
                }
            }
            .onAppear {
                if let depositInfo = account.depositInfo {
                    rateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                isRateFocused = true
            }
        }
    }
    
    private func saveRateChange() {
        guard let rate = AmountFormatter.parse(rateText) else { return }
        
        let dateString = DateFormatters.dateFormatter.string(from: effectiveFromDate)
        let note = noteText.isEmpty ? nil : noteText
        
        depositsViewModel.addDepositRateChange(
            accountId: account.id,
            effectiveFrom: dateString,
            annualRate: rate,
            note: note
        )
        
        onComplete()
    }
}

#Preview("Deposit Rate Change") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "test",
        name: "Test Deposit",
        balance: 1000000,
        currency: "KZT",
        bankLogo: .halykBank,
        depositInfo: DepositInfo(
            bankName: "Halyk Bank",
            principalBalance: Decimal(1000000),
            capitalizationEnabled: true,
            interestRateAnnual: Decimal(12.5),
            interestPostingDay: 15
        )
    )
    
    DepositRateChangeView(
        depositsViewModel: coordinator.depositsViewModel,
        account: sampleAccount,
        onComplete: {}
    )
}
