//
//  LoanEditView.swift
//  Tenra
//
//  View for creating, editing, and converting accounts to loans/installments.
//  3 modes: new, edit, convert (mirrors DepositEditView pattern).
//  Migrated to hero-style UI with EditableHeroSection.
//

import SwiftUI

struct LoanEditView: View {
    let loansViewModel: LoansViewModel
    let account: Account?
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var appCoordinator

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
    @State private var validationError: String? = nil

    // Default tagging — pre-fills LoanPaymentView / LoanEarlyRepaymentView for
    // every payment of this loan unless the user has already recorded one (then
    // that prior payment's category wins). Optional == no default.
    //
    // NOTE: `LoanInfo.defaultSubcategoryIds` stays as `[String]` for forward-
    // compatibility (multi-select may return later), but the loan-edit form
    // uses single-select dropdowns to mirror `SubscriptionEditView`'s style.
    @State private var defaultCategory: String? = nil
    @State private var defaultSubcategoryId: String? = nil

    /// Resolves the active `CustomCategory.id` for the picked default category —
    /// needed to enumerate subcategory options.
    private var defaultCategoryId: String? {
        guard let name = defaultCategory else { return nil }
        return appCoordinator.categoriesViewModel.customCategories.first { $0.name == name }?.id
    }

    /// Active expense-catalog category names. Mirrors `LoanDetailView.expense
    /// PickerCategories` so the same options surface in both creation and
    /// payment flows. Excludes deleted/historical strings.
    private var expensePickerCategories: [String] {
        appCoordinator.categoriesViewModel.customCategories
            .filter { $0.type == .expense }
            .map(\.name)
            .sortedByCustomOrder(
                customCategories: appCoordinator.categoriesViewModel.customCategories,
                type: .expense
            )
    }

    /// Categories surfaced in the default-category dropdown. Always prefixed
    /// with a `nil` "no default" option so the user can clear the selection.
    private var categoryDropdownOptions: [(label: String, value: String?)] {
        let none: (label: String, value: String?) = (
            label: String(localized: "loan.noDefaultCategory", defaultValue: "Без категории"),
            value: nil
        )
        return [none] + expensePickerCategories.map { (label: $0, value: Optional($0)) }
    }

    /// Subcategories of the picked default category, prefixed with "no default".
    /// Empty (no rows beyond "None") when the picked category has no subcategories.
    private var subcategoryDropdownOptions: [(label: String, value: String?)] {
        let none: (label: String, value: String?) = (
            label: String(localized: "loan.noDefaultSubcategory", defaultValue: "Без подкатегории"),
            value: nil
        )
        guard let categoryId = defaultCategoryId else { return [none] }
        let subs = appCoordinator.categoriesViewModel
            .getSubcategoriesForCategory(categoryId)
            .map { (label: $0.name, value: Optional($0.id)) }
        return [none] + subs
    }

    /// `true` when the picked default category has at least one subcategory in
    /// the catalog — controls whether the second dropdown is rendered at all.
    private var defaultCategoryHasSubcategories: Bool {
        guard let categoryId = defaultCategoryId else { return false }
        return !appCoordinator.categoriesViewModel.getSubcategoriesForCategory(categoryId).isEmpty
    }


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
            wrapInForm: false,
            onSave: saveLoan,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section: Icon, Name, Amount, Currency
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $name,
                        balance: $principalAmountText,
                        currency: $currency,
                        titlePlaceholder: String(localized: "loan.namePlaceholder", defaultValue: "e.g. Car Loan"),
                        config: .accountHero
                    )

                    // Validation Error
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.lg)
                    }

                    // Loan details: bank, type, interest rate
                    FormSection(header: String(localized: "loan.detailsSection", defaultValue: "Loan Details")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("building.columns", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.bankLabel", defaultValue: "Bank"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.bankPlaceholder", defaultValue: "Bank name"),
                                text: $bankName
                            )
                            .inlineFieldStyle()
                        }

                        Divider()

                        // Loan type segmented picker
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Picker(String(localized: "loan.typePicker", defaultValue: "Type"), selection: $loanType) {
                                Text(String(localized: "loan.typeAnnuity", defaultValue: "Annuity (Credit)")).tag(LoanType.annuity)
                                Text(String(localized: "loan.typeInstallment", defaultValue: "Installment")).tag(LoanType.installment)
                            }
                            .pickerStyle(.segmented)
                            .disabled(isEditing)

                            if isEditing {
                                Text(String(localized: "loan.typeLockedHint", defaultValue: "Loan type cannot be changed after creation"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            } else if loanType == .installment {
                                Text(String(localized: "loan.installmentHint", defaultValue: "Installment = 0% interest, equal payments"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.lg)

                        if loanType == .annuity {
                            Divider()

                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("percent", color: AppColors.accent, size: AppIconSize.lg)
                            ) {
                                Text(String(localized: "loan.interestRateLabel", defaultValue: "Interest rate"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                HStack(spacing: AppSpacing.xs) {
                                    TextField("0.0", text: $interestRateText)
                                        .inlineFieldStyle(keyboard: .decimalPad, maxWidth: 80)
                                    Text(String(localized: "loan.rateAnnualSuffix", defaultValue: "% annual"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Loan schedule: term, payment day, start date
                    FormSection(header: String(localized: "loan.scheduleSection", defaultValue: "Schedule")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("clock", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.termLabel", defaultValue: "Term"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0", text: $termMonthsText)
                                    .inlineFieldStyle(keyboard: .numberPad, maxWidth: 60)
                                Text(String(localized: "loan.months", defaultValue: "months"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider()

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("calendar.badge.clock", color: AppColors.accent, size: AppIconSize.lg)
                        ) {
                            Text(String(localized: "loan.paymentDay", defaultValue: "Payment day"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.sm) {
                                Text("\(paymentDay)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(minWidth: 28, alignment: .trailing)
                                Stepper("", value: $paymentDay, in: 1...31)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }

                        if !isEditing {
                            Divider()
                            DatePickerRow(
                                icon: "calendar",
                                title: String(localized: "loan.startDate", defaultValue: "Loan start date"),
                                selection: $startDate
                            )
                        }
                    }

                    // Default category + subcategories. These pre-fill the
                    // LoanPaymentView form for every payment of this loan, so
                    // recurring monthly payments don't require re-tagging from
                    // scratch. Stored on `LoanInfo`; empty == no default.
                    defaultTaggingSection
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear {
            if let account = account, let loanInfo = account.loanInfo {
                // Editing existing loan
                name = account.name
                bankName = loanInfo.bankName
                principalAmountText = AmountInputFormatting.bindingString(for: loanInfo.originalPrincipal)
                currency = account.currency
                selectedIconSource = account.iconSource
                loanType = loanInfo.loanType
                interestRateText = AmountInputFormatting.bindingString(for: loanInfo.interestRateAnnual)
                termMonthsText = "\(loanInfo.termMonths)"
                paymentDay = loanInfo.paymentDay
                if let start = DateFormatters.dateFormatter.date(from: loanInfo.startDate) {
                    startDate = start
                }
                // Pre-fill default tagging from the persisted LoanInfo. Skip the
                // legacy `Loan Payment` sentinel in case it leaked into a default.
                if let stored = loanInfo.defaultCategory,
                   stored != TransactionType.loanPaymentCategoryName,
                   expensePickerCategories.contains(stored) {
                    defaultCategory = stored
                }
                // Single-default convention: pick the first stored id (legacy
                // multi-select rows collapse to their first entry).
                defaultSubcategoryId = loanInfo.defaultSubcategoryIds.first
            } else if let account = account {
                // Converting regular account → loan: pre-fill from account
                name = account.name
                currency = account.currency
                selectedIconSource = account.iconSource
                principalAmountText = AmountInputFormatting.bindingString(for: account.balance)
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
    }

    // MARK: - Default Tagging Section

    @ViewBuilder
    private var defaultTaggingSection: some View {
        if !expensePickerCategories.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                FormSection(header: String(localized: "loan.defaultTagging", defaultValue: "Default category")) {
                    MenuPickerRow(
                        icon: "tag",
                        title: String(localized: "subscriptions.category", defaultValue: "Category"),
                        selection: $defaultCategory,
                        options: categoryDropdownOptions
                    )

                    if defaultCategoryHasSubcategories {
                        Divider()

                        MenuPickerRow(
                            icon: "tag.fill",
                            title: String(localized: "loan.subcategoryHeader", defaultValue: "Subcategory"),
                            selection: $defaultSubcategoryId,
                            options: subcategoryDropdownOptions
                        )
                    }
                }

                Text(String(
                    localized: "loan.defaultTaggingHint",
                    defaultValue: "Pre-fills the payment form. Last-used category from previous payments takes precedence."
                ))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.lg)
            }
            .onChange(of: defaultCategory) { oldValue, newValue in
                // Subcategory ids are scoped to a single category — clear the
                // selection when the user switches the parent category so the
                // dropdown's selected value isn't stale.
                if oldValue != newValue {
                    defaultSubcategoryId = nil
                }
            }
        }
    }

    // MARK: - Save

    private func saveLoan() {
        guard let principalAmount = AmountFormatter.parse(principalAmountText) else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
            }
            HapticManager.error()
            return
        }
        guard let termMonths = Int(termMonthsText), termMonths > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidTerm", defaultValue: "Enter a valid term")
            }
            HapticManager.error()
            return
        }

        let interestRate: Decimal
        if loanType == .annuity {
            guard let rate = AmountFormatter.parse(interestRateText) else {
                withAnimation(AppAnimation.contentSpring) {
                    validationError = String(localized: "loan.error.invalidRate", defaultValue: "Enter a valid interest rate")
                }
                HapticManager.error()
                return
            }
            interestRate = rate
        } else {
            interestRate = 0
        }
        validationError = nil

        let existingInfo = account?.loanInfo
        let startDateStr = isEditing
            ? (existingInfo?.startDate ?? DateFormatters.dateFormatter.string(from: startDate))
            : DateFormatters.dateFormatter.string(from: startDate)

        // Recalculate monthly payment when principal, rate, or term changed
        let shouldRecalculate: Bool
        if let existing = existingInfo {
            shouldRecalculate = principalAmount != existing.originalPrincipal
                || interestRate != existing.interestRateAnnual
                || termMonths != existing.termMonths
        } else {
            shouldRecalculate = true // New loan — always calculate
        }

        let monthlyPayment: Decimal?
        if shouldRecalculate {
            monthlyPayment = nil // LoanInfo.init will calculate via LoanPaymentService
        } else {
            monthlyPayment = existingInfo?.monthlyPayment
        }

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
            monthlyPayment: monthlyPayment,
            paymentDay: paymentDay,
            paymentsMade: existingInfo?.paymentsMade ?? 0,
            lastPaymentDate: existingInfo?.lastPaymentDate,
            earlyRepayments: existingInfo?.earlyRepayments ?? [],
            defaultCategory: defaultCategory,
            defaultSubcategoryIds: defaultSubcategoryId.map { [$0] } ?? []
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

// MARK: - Previews

#Preview("Loan Edit - New") {
    let coordinator = AppCoordinator()

    LoanEditView(
        loansViewModel: coordinator.loansViewModel,
        account: nil,
        onSave: { _ in }
    )
    .environment(coordinator)
}

#Preview("Loan Edit - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "preview-loan",
        name: "Car Loan",
        currency: "KZT",
        iconSource: .brandService("halykbank.kz"),
        loanInfo: LoanInfo(
            bankName: "Halyk Bank",
            loanType: .annuity,
            originalPrincipal: 5_000_000,
            remainingPrincipal: 3_500_000,
            interestRateAnnual: 18.5,
            termMonths: 36,
            startDate: "2025-06-01",
            paymentDay: 15,
            paymentsMade: 9
        ),
        initialBalance: 5_000_000
    )

    LoanEditView(
        loansViewModel: coordinator.loansViewModel,
        account: sampleAccount,
        onSave: { _ in }
    )
    .environment(coordinator)
}
