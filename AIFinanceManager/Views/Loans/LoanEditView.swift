//
//  LoanEditView.swift
//  AIFinanceManager
//
//  View for creating, editing, and converting accounts to loans/installments.
//  3 modes: new, edit, convert (mirrors DepositEditView pattern).
//

import SwiftUI

struct LoanEditView: View {
    let loansViewModel: LoansViewModel
    let account: Account?
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalAmountText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedIconSource: IconSource? = nil
    @State private var loanType: LoanType = .annuity
    @State private var interestRateText: String = ""
    @State private var termMonthsText: String = ""
    @State private var paymentDay: Int = 1
    @State private var startDate: Date = Date()
    @State private var showingIconPicker = false
    @FocusState private var isNameFocused: Bool

    private let currencies = ["KZT", "USD", "EUR"]

    /// True when converting a regular account → loan (account exists but has no loanInfo)
    private var isConverting: Bool {
        account != nil && account?.loanInfo == nil
    }

    private var isEditing: Bool {
        account != nil && account?.loanInfo != nil
    }

    private var title: String {
        if isConverting {
            return String(localized: "loan.convertTitle", defaultValue: "Convert to Loan")
        } else if isEditing {
            return String(localized: "loan.editTitle", defaultValue: "Edit Loan")
        } else {
            return String(localized: "loan.newTitle", defaultValue: "New Loan")
        }
    }

    private var isSaveDisabled: Bool {
        name.isEmpty || bankName.isEmpty || principalAmountText.isEmpty || termMonthsText.isEmpty
        || (loanType == .annuity && interestRateText.isEmpty)
    }

    var body: some View {
        EditSheetContainer(
            title: title,
            isSaveDisabled: isSaveDisabled,
            onSave: saveLoan,
            onCancel: { dismiss() }
        ) {
            Section(header: Text(String(localized: "loan.nameHeader", defaultValue: "Name"))) {
                TextField(String(localized: "loan.namePlaceholder", defaultValue: "e.g. Car Loan"), text: $name)
                    .focused($isNameFocused)
            }

            Section(header: Text(String(localized: "loan.bankHeader", defaultValue: "Bank"))) {
                TextField(String(localized: "loan.bankPlaceholder", defaultValue: "Bank name"), text: $bankName)

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
                            .font(AppTypography.caption)
                    }
                }
            }

            Section(header: Text(String(localized: "loan.typeHeader", defaultValue: "Loan Type"))) {
                Picker(String(localized: "loan.typePicker", defaultValue: "Type"), selection: $loanType) {
                    Text(String(localized: "loan.typeAnnuity", defaultValue: "Annuity (Credit)")).tag(LoanType.annuity)
                    Text(String(localized: "loan.typeInstallment", defaultValue: "Installment")).tag(LoanType.installment)
                }
                .pickerStyle(.segmented)
                .disabled(isEditing)

                if isEditing {
                    Text(String(localized: "loan.typeLockedHint", defaultValue: "Loan type cannot be changed after creation"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                } else if loanType == .installment {
                    Text(String(localized: "loan.installmentHint", defaultValue: "Installment = 0% interest, equal payments"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(String(localized: "common.currency"))) {
                Picker(String(localized: "common.currency"), selection: $currency) {
                    ForEach(currencies, id: \.self) { curr in
                        Text("\(Formatting.currencySymbol(for: curr)) \(curr)").tag(curr)
                    }
                }
            }

            Section(header: Text(String(localized: "loan.principalHeader", defaultValue: "Loan Amount"))) {
                TextField(String(localized: "loan.principalPlaceholder", defaultValue: "Total loan amount"), text: $principalAmountText)
                    .keyboardType(.decimalPad)
            }

            if loanType == .annuity {
                Section(header: Text(String(localized: "loan.interestRateHeader", defaultValue: "Interest Rate"))) {
                    HStack {
                        TextField("0.0", text: $interestRateText)
                            .keyboardType(.decimalPad)
                        Text(String(localized: "loan.rateAnnual", defaultValue: "% annual"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text(String(localized: "loan.termHeader", defaultValue: "Term"))) {
                HStack {
                    TextField(String(localized: "loan.termPlaceholder", defaultValue: "Number of months"), text: $termMonthsText)
                        .keyboardType(.numberPad)
                    Text(String(localized: "loan.months", defaultValue: "months"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(String(localized: "loan.paymentDayHeader", defaultValue: "Payment Day"))) {
                Picker(String(localized: "loan.paymentDay", defaultValue: "Day of month"), selection: $paymentDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                Text(String(localized: "loan.paymentDayHint", defaultValue: "Day of month when payment is due"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if !isEditing {
                Section(header: Text(String(localized: "loan.startDateHeader", defaultValue: "Start Date"))) {
                    DatePicker(
                        String(localized: "loan.startDate", defaultValue: "Loan start date"),
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }
            }
        }
        .onAppear {
            if let account = account, let loanInfo = account.loanInfo {
                // Editing existing loan
                name = account.name
                bankName = loanInfo.bankName
                principalAmountText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue)
                currency = account.currency
                selectedIconSource = account.iconSource
                loanType = loanInfo.loanType
                interestRateText = String(format: "%.2f", NSDecimalNumber(decimal: loanInfo.interestRateAnnual).doubleValue)
                termMonthsText = "\(loanInfo.termMonths)"
                paymentDay = loanInfo.paymentDay
                if let start = DateFormatters.dateFormatter.date(from: loanInfo.startDate) {
                    startDate = start
                }
            } else if let account = account {
                // Converting regular account → loan: pre-fill from account
                name = account.name
                currency = account.currency
                selectedIconSource = account.iconSource
                principalAmountText = String(format: "%.2f", account.balance)
            } else {
                // New loan
                currency = "KZT"
                selectedIconSource = nil
                principalAmountText = ""
                interestRateText = ""
                termMonthsText = ""
                paymentDay = 1
                startDate = Date()
            }
        }
        .task {
            guard account == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $selectedIconSource)
        }
    }

    // MARK: - Save

    private func saveLoan() {
        guard let principalAmount = AmountFormatter.parse(principalAmountText),
              let termMonths = Int(termMonthsText), termMonths > 0 else {
            return
        }

        let interestRate: Decimal
        if loanType == .annuity {
            guard let rate = AmountFormatter.parse(interestRateText) else { return }
            interestRate = rate
        } else {
            interestRate = 0
        }

        let existingInfo = account?.loanInfo
        let startDateStr = isEditing
            ? (existingInfo?.startDate ?? DateFormatters.dateFormatter.string(from: startDate))
            : DateFormatters.dateFormatter.string(from: startDate)

        let loanInfo = LoanInfo(
            bankName: bankName,
            loanType: loanType,
            originalPrincipal: principalAmount,
            remainingPrincipal: existingInfo?.remainingPrincipal ?? principalAmount,
            interestRateAnnual: interestRate,
            interestRateHistory: existingInfo?.interestRateHistory,
            totalInterestPaid: existingInfo?.totalInterestPaid ?? 0,
            termMonths: termMonths,
            startDate: startDateStr,
            endDate: existingInfo?.endDate,
            monthlyPayment: existingInfo?.monthlyPayment,
            paymentDay: paymentDay,
            paymentsMade: existingInfo?.paymentsMade ?? 0,
            lastPaymentDate: existingInfo?.lastPaymentDate,
            lastReconciliationDate: existingInfo?.lastReconciliationDate,
            earlyRepayments: existingInfo?.earlyRepayments ?? []
        )

        let balance = NSDecimalNumber(decimal: principalAmount).doubleValue
        let newAccount = Account(
            id: account?.id ?? UUID().uuidString,
            name: name,
            currency: currency,
            iconSource: selectedIconSource,
            loanInfo: loanInfo,
            shouldCalculateFromTransactions: false,
            initialBalance: balance,
            order: account?.order
        )

        HapticManager.success()
        onSave(newAccount)
    }
}
