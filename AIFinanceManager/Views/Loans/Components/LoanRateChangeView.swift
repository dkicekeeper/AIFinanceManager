//
//  LoanRateChangeView.swift
//  AIFinanceManager
//
//  Rate change view for loans (mirrors DepositRateChangeView pattern)
//

import SwiftUI

struct LoanRateChangeView: View {
    let account: Account
    let onRateChanged: (String, Decimal, String?) -> Void // (effectiveFrom, annualRate, note)

    @Environment(\.dismiss) private var dismiss

    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""
    @FocusState private var isRateFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "loan.newRate", defaultValue: "New Interest Rate"))) {
                    HStack {
                        TextField("0.0", text: $rateText)
                            .keyboardType(.decimalPad)
                            .focused($isRateFocused)
                        Text(String(localized: "loan.rateAnnual", defaultValue: "% annual"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text(String(localized: "loan.effectiveDate", defaultValue: "Effective From"))) {
                    DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $effectiveFromDate, displayedComponents: .date)
                }

                if let loanInfo = account.loanInfo {
                    Section(header: Text(String(localized: "loan.rateChangeImpact", defaultValue: "Impact"))) {
                        if let newRate = AmountFormatter.parse(rateText), newRate > 0 {
                            let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)
                            let newPayment = LoanPaymentService.calculateMonthlyPayment(
                                principal: loanInfo.remainingPrincipal,
                                annualRate: newRate,
                                termMonths: remaining
                            )
                            let diff = newPayment - loanInfo.monthlyPayment

                            InfoRow(
                                icon: "banknote",
                                label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                                value: Formatting.formatCurrency(NSDecimalNumber(decimal: newPayment).doubleValue, currency: account.currency)
                            )

                            let diffAmount = NSDecimalNumber(decimal: diff).doubleValue
                            InfoRow(
                                icon: diff > 0 ? "arrow.up" : "arrow.down",
                                label: String(localized: "loan.paymentChange", defaultValue: "Change"),
                                value: String(format: "%@%@", diff > 0 ? "+" : "", Formatting.formatCurrency(diffAmount, currency: account.currency))
                            )
                        } else {
                            Text(String(localized: "loan.enterRateForPreview", defaultValue: "Enter rate to see impact"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text(String(localized: "loan.note", defaultValue: "Note"))) {
                    TextField(String(localized: "loan.notePlaceholder", defaultValue: "Optional note"), text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: "loan.changeRateTitle", defaultValue: "Change Rate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "button.cancel")) {
                        HapticManager.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.save")) {
                        saveRateChange()
                    }
                    .disabled(rateText.isEmpty)
                }
            }
            .onAppear {
                if let loanInfo = account.loanInfo {
                    rateText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.interestRateAnnual).doubleValue)
                }
            }
            .task {
                await Task.yield()
                isRateFocused = true
            }
        }
    }

    private func saveRateChange() {
        guard let rate = AmountFormatter.parse(rateText) else { return }

        let dateString = DateFormatters.dateFormatter.string(from: effectiveFromDate)
        let note = noteText.isEmpty ? nil : noteText

        onRateChanged(dateString, rate, note)
        HapticManager.success()
        dismiss()
    }
}
