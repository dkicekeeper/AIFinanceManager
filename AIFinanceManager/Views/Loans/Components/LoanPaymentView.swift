//
//  LoanPaymentView.swift
//  AIFinanceManager
//
//  View for making a manual monthly loan payment.
//  Selects a source bank account and records the payment.
//

import SwiftUI

struct LoanPaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let availableAccounts: [Account]
    let onPayment: (Decimal, String, String) -> Void // (amount, date, sourceAccountId)

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String = ""
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "loan.paymentAmount", defaultValue: "Payment Amount"))) {
                    HStack {
                        TextField(String(localized: "loan.amountPlaceholder", defaultValue: "Amount"), text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                        Text(Formatting.currencySymbol(for: account.currency))
                            .foregroundStyle(.secondary)
                    }

                    Text(String(format: String(localized: "loan.scheduledPayment", defaultValue: "Scheduled: %@"), Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue, currency: account.currency)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(String(localized: "loan.sourceAccount", defaultValue: "Source Account"))) {
                    if availableAccounts.isEmpty {
                        Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts available"))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(String(localized: "loan.selectSourceAccount", defaultValue: "Select account to pay from"), selection: $selectedSourceAccountId) {
                            Text(String(localized: "loan.selectSourceAccount", defaultValue: "Select account to pay from"))
                                .tag("")
                            ForEach(availableAccounts) { acc in
                                Text(acc.name)
                                    .tag(acc.id)
                            }
                        }
                    }
                }

                Section(header: Text(String(localized: "loan.repaymentDate", defaultValue: "Date"))) {
                    DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $paymentDate, displayedComponents: .date)
                }

                // Payment breakdown preview
                if let amount = AmountFormatter.parse(amountText), amount > 0 {
                    Section(header: Text(String(localized: "loan.impact", defaultValue: "Impact"))) {
                        let breakdown = LoanPaymentService.paymentBreakdown(
                            remainingPrincipal: loanInfo.remainingPrincipal,
                            annualRate: loanInfo.interestRateAnnual,
                            monthlyPayment: amount
                        )
                        InfoRow(
                            icon: "percent",
                            label: String(localized: "loan.interestPortion", defaultValue: "Interest"),
                            value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.interest).doubleValue, currency: account.currency)
                        )
                        InfoRow(
                            icon: "arrow.down.to.line",
                            label: String(localized: "loan.principalPortion", defaultValue: "Principal"),
                            value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.principal).doubleValue, currency: account.currency)
                        )
                    }
                }
            }
            .navigationTitle(String(localized: "loan.paymentTitle", defaultValue: "Loan Payment"))
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
                        savePayment()
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                amountText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue)
                if selectedSourceAccountId.isEmpty, let first = availableAccounts.first {
                    selectedSourceAccountId = first.id
                }
            }
            .task {
                await Task.yield()
                isAmountFocused = true
            }
        }
    }

    private var isFormValid: Bool {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return false }
        return !selectedSourceAccountId.isEmpty
    }

    private func savePayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return }

        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        onPayment(amount, dateStr, selectedSourceAccountId)
        HapticManager.success()
        dismiss()
    }
}
