//
//  LoanEarlyRepaymentView.swift
//  AIFinanceManager
//
//  View for making early repayments on loans.
//  Shows impact on remaining term or monthly payment.
//

import SwiftUI

struct LoanEarlyRepaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let onRepayment: (Decimal, String, EarlyRepaymentType, String?) -> Void // (amount, date, type, note)

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var repaymentDate: Date = Date()
    @State private var repaymentType: EarlyRepaymentType = .reduceTerm
    @State private var noteText: String = ""
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "loan.repaymentAmount", defaultValue: "Repayment Amount"))) {
                    HStack {
                        TextField(String(localized: "loan.amountPlaceholder", defaultValue: "Amount"), text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                        Text(Formatting.currencySymbol(for: account.currency))
                            .foregroundStyle(.secondary)
                    }

                    Text(String(format: String(localized: "loan.remainingBalance", defaultValue: "Remaining: %@"), Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue, currency: account.currency)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(String(localized: "loan.repaymentDate", defaultValue: "Date"))) {
                    DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $repaymentDate, displayedComponents: .date)
                }

                Section(header: Text(String(localized: "loan.repaymentType", defaultValue: "Repayment Strategy"))) {
                    Picker(String(localized: "loan.strategy", defaultValue: "Strategy"), selection: $repaymentType) {
                        Text(String(localized: "loan.reduceTerm", defaultValue: "Reduce Term")).tag(EarlyRepaymentType.reduceTerm)
                        Text(String(localized: "loan.reducePayment", defaultValue: "Reduce Payment")).tag(EarlyRepaymentType.reducePayment)
                    }
                    .pickerStyle(.segmented)

                    Text(repaymentType == .reduceTerm
                         ? String(localized: "loan.reduceTermHint", defaultValue: "Keep monthly payment, finish sooner")
                         : String(localized: "loan.reducePaymentHint", defaultValue: "Keep term, lower monthly payment"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }

                // Impact preview
                if let amount = AmountFormatter.parse(amountText), amount > 0, amount <= loanInfo.remainingPrincipal {
                    Section(header: Text(String(localized: "loan.impact", defaultValue: "Impact"))) {
                        impactPreview(amount: amount)
                    }
                }

                Section(header: Text(String(localized: "loan.note", defaultValue: "Note"))) {
                    TextField(String(localized: "loan.notePlaceholder", defaultValue: "Optional note"), text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(String(localized: "loan.earlyRepaymentTitle", defaultValue: "Early Repayment"))
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
                        saveRepayment()
                    }
                    .disabled(amountText.isEmpty)
                }
            }
            .task {
                await Task.yield()
                isAmountFocused = true
            }
        }
    }

    private func computePreview(amount: Decimal) -> LoanInfo {
        var preview = loanInfo
        let dateStr = DateFormatters.dateFormatter.string(from: repaymentDate)
        LoanPaymentService.applyEarlyRepayment(
            loanInfo: &preview,
            amount: amount,
            date: dateStr,
            type: repaymentType
        )
        return preview
    }

    @ViewBuilder
    private func impactPreview(amount: Decimal) -> some View {
        let preview = computePreview(amount: amount)

        switch repaymentType {
        case .reduceTerm:
            InfoRow(
                icon: "calendar.badge.minus",
                label: String(localized: "loan.termReduction", defaultValue: "Term reduced by"),
                value: String(format: String(localized: "loan.monthsValue", defaultValue: "%d months"), loanInfo.termMonths - preview.termMonths)
            )
            InfoRow(
                icon: "calendar",
                label: String(localized: "loan.newEndDate", defaultValue: "New end date"),
                value: formatDateString(preview.endDate)
            )
        case .reducePayment:
            InfoRow(
                icon: "arrow.down.circle",
                label: String(localized: "loan.paymentReduction", defaultValue: "Payment reduced by"),
                value: Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.monthlyPayment - preview.monthlyPayment).doubleValue, currency: account.currency)
            )
            InfoRow(
                icon: "banknote",
                label: String(localized: "loan.newMonthlyPayment", defaultValue: "New monthly payment"),
                value: Formatting.formatCurrency(NSDecimalNumber(decimal: preview.monthlyPayment).doubleValue, currency: account.currency)
            )
        }
    }

    private func saveRepayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return }

        let dateStr = DateFormatters.dateFormatter.string(from: repaymentDate)
        let note = noteText.isEmpty ? nil : noteText

        onRepayment(amount, dateStr, repaymentType, note)
        HapticManager.success()
        dismiss()
    }

    private func formatDateString(_ dateStr: String) -> String {
        if let date = DateFormatters.dateFormatter.date(from: dateStr) {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return dateStr
    }
}
