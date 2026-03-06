//
//  LoanPayAllView.swift
//  AIFinanceManager
//
//  View for paying all monthly loan payments at once
//  from a selected source bank account.
//

import SwiftUI

struct LoanPayAllView: View {
    let activeLoans: [Account]
    let availableAccounts: [Account]
    let currency: String
    let onPayAll: (String, String) -> Void // (sourceAccountId, dateStr)

    @Environment(\.dismiss) private var dismiss

    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String = ""

    private var totalPayment: Decimal {
        activeLoans.compactMap { $0.loanInfo?.monthlyPayment }.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Loan list
                Section(header: Text(String(localized: "loan.payAllTitle", defaultValue: "Pay All Loans"))) {
                    ForEach(activeLoans) { loan in
                        if let loanInfo = loan.loanInfo {
                            HStack {
                                IconView(source: loan.iconSource, size: AppIconSize.md)

                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text(loan.name)
                                        .font(AppTypography.bodySmall)
                                    Text(loanInfo.bankName)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue, currency: loan.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.expense)
                            }
                        }
                    }
                }

                // Total
                Section {
                    HStack {
                        Text(String(localized: "loan.payAllTotal", defaultValue: "Total Payment"))
                            .font(AppTypography.bodyEmphasis)
                        Spacer()
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: totalPayment).doubleValue,
                            currency: currency,
                            fontSize: AppTypography.bodyEmphasis,
                            color: AppColors.expense
                        )
                    }
                }

                // Source account
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

                // Date
                Section(header: Text(String(localized: "loan.repaymentDate", defaultValue: "Date"))) {
                    DatePicker(String(localized: "loan.date", defaultValue: "Date"), selection: $paymentDate, displayedComponents: .date)
                }
            }
            .navigationTitle(String(localized: "loan.payAllTitle", defaultValue: "Pay All Loans"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "button.cancel")) {
                        HapticManager.light()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "loan.payAllConfirm", defaultValue: "Pay All")) {
                        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
                        onPayAll(selectedSourceAccountId, dateStr)
                        HapticManager.success()
                        dismiss()
                    }
                    .disabled(selectedSourceAccountId.isEmpty || activeLoans.isEmpty)
                }
            }
            .onAppear {
                if selectedSourceAccountId.isEmpty, let first = availableAccounts.first {
                    selectedSourceAccountId = first.id
                }
            }
        }
    }
}
