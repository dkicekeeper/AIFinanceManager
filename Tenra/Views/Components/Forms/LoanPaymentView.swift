//
//  LoanPaymentView.swift
//  Tenra
//
//  View for making a manual monthly loan payment.
//  Selects a source bank account and records the payment.
//

import SwiftUI

/// Outcome of `LoanPaymentView` collected on save and forwarded to the caller for
/// persistence. Bundling the fields into a struct keeps the closure signature
/// readable as the form grows (amount + date + source + note + category + subcategories).
struct LoanPaymentFormResult {
    let amount: Decimal
    let date: String
    let sourceAccountId: String
    let note: String?
    /// `nil` means "keep the technical default" (e.g. `Loan Payment` for new payments).
    /// Non-nil values come from the expense catalog and tag the payment alongside
    /// regular spending.
    let category: String?
    let subcategoryIds: Set<String>
}

struct LoanPaymentView: View {
    let account: Account
    let loanInfo: LoanInfo
    let availableAccounts: [Account]
    /// Optional: amount of the most recent linked loan-payment for this loan, used as
    /// the default value in the amount field. If `nil`, falls back to `loanInfo.monthlyPayment`.
    var lastPaidAmount: Decimal? = nil
    /// Expense-catalog categories the user can assign to this payment. When empty
    /// the picker is hidden and `category` defaults to the technical
    /// `Loan Payment` constant.
    var availableCategories: [String] = []
    var customCategories: [CustomCategory] = []
    var categoriesViewModel: CategoriesViewModel? = nil
    /// Pre-selected category (e.g. the one used for the previous payment of this loan).
    var initialCategory: String? = nil
    let onPayment: (LoanPaymentFormResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var paymentDate: Date = Date()
    @State private var selectedSourceAccountId: String = ""
    @State private var noteText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch: Bool = false
    @State private var subcategorySearchText: String = ""
    @FocusState private var isAmountFocused: Bool

    @State private var validationError: String? = nil

    /// Resolves the custom-category id for the currently selected category — needed
    /// to feed `SubcategorySelectorView`.
    private var selectedCategoryId: String? {
        guard let name = selectedCategory else { return nil }
        return customCategories.first { $0.name == name }?.id
    }

    private var scheduledHint: String {
        String(
            format: String(localized: "loan.scheduledPayment", defaultValue: "Scheduled: %@"),
            Formatting.formatCurrency(
                NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue,
                currency: account.currency
            )
        )
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "loan.paymentTitle", defaultValue: "Loan Payment"),
            isSaveDisabled: !isFormValid,
            wrapInForm: false,
            onSave: { savePayment() },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                    }

                    // Amount + Source + Date in one card
                    FormSection {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("banknote", color: AppColors.accent, size: AppIconSize.lg),
                            hint: scheduledHint
                        ) {
                            Text(String(localized: "loan.amountLabel", defaultValue: "Amount"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField(
                                    String(localized: "loan.amountPlaceholder", defaultValue: "Amount"),
                                    text: $amountText
                                )
                                .inlineFieldStyle(keyboard: .decimalPad)
                                .focused($isAmountFocused)
                                Text(Formatting.currencySymbol(for: account.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        if availableAccounts.isEmpty {
                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("building.columns", color: AppColors.accent, size: AppIconSize.lg)
                            ) {
                                Text(String(localized: "loan.sourceAccount", defaultValue: "From account"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } else {
                            MenuPickerRow(
                                icon: "building.columns",
                                title: String(localized: "loan.sourceAccount", defaultValue: "From account"),
                                selection: $selectedSourceAccountId,
                                options: availableAccounts.map { (label: $0.name, value: $0.id) }
                            )
                        }

                        Divider().padding(.leading, AppSpacing.lg)

                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "loan.date", defaultValue: "Date"),
                            selection: $paymentDate
                        )
                    }

                    // Category — pulled from the expense catalog so users can tag
                    // a loan payment with "Auto" / "Mortgage" / etc. just like a
                    // subscription. Defaults to the previous payment's category when
                    // available, or no category (technical "Loan Payment").
                    if !availableCategories.isEmpty {
                        CategorySelectorView(
                            categories: availableCategories,
                            type: .expense,
                            customCategories: customCategories,
                            selectedCategory: $selectedCategory,
                            onSelectionChange: { newValue in
                                // When the category changes we must drop subcategory
                                // selections — they're scoped to a single category id.
                                if newValue != selectedCategory {
                                    selectedSubcategoryIds.removeAll()
                                }
                            },
                            emptyStateMessage: nil
                        )
                    }

                    // Subcategory tags — only shown after a category is picked AND
                    // there's at least one subcategory available for it (the inner
                    // view collapses to nothing when its catalog is empty).
                    if let categoriesVM = categoriesViewModel,
                       selectedCategoryId != nil {
                        SubcategorySelectorView(
                            categoriesViewModel: categoriesVM,
                            categoryId: selectedCategoryId,
                            selectedSubcategoryIds: $selectedSubcategoryIds,
                            onSearchTap: {
                                withAnimation { showingSubcategorySearch = true }
                            }
                        )
                    }

                    // Optional note — surfaces as the transaction's `description`
                    // so users can annotate ad-hoc payments (extra payment, partial,
                    // etc.) without going back to edit the transaction.
                    FormTextField(
                        text: $noteText,
                        placeholder: String(localized: "loan.notePlaceholder", defaultValue: "Note (optional)"),
                        style: .multiline(min: 2, max: 4)
                    )

                    // Impact preview (conditional second section)
                    if let amount = AmountFormatter.parse(amountText), amount > 0 {
                        let breakdown = LoanPaymentService.paymentBreakdown(
                            remainingPrincipal: loanInfo.remainingPrincipal,
                            annualRate: loanInfo.interestRateAnnual,
                            monthlyPayment: amount
                        )
                        FormSection(header: String(localized: "loan.impact", defaultValue: "Impact")) {
                            InfoRow(
                                icon: "percent",
                                label: String(localized: "loan.interestPortion", defaultValue: "Interest"),
                                value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.interest).doubleValue, currency: account.currency)
                            )
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                            Divider().padding(.leading, AppSpacing.lg)
                            InfoRow(
                                icon: "arrow.down.to.line",
                                label: String(localized: "loan.principalPortion", defaultValue: "Principal"),
                                value: Formatting.formatCurrency(NSDecimalNumber(decimal: breakdown.principal).doubleValue, currency: account.currency)
                            )
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .onAppear {
            // Default to the most recently paid amount if available — users typically
            // round their actual payment (e.g. 340 000) above the calculated annuity
            // (e.g. 336 829) and the prior actual is the better suggestion.
            let defaultAmount = lastPaidAmount ?? loanInfo.monthlyPayment
            amountText = AmountInputFormatting.bindingString(for: defaultAmount)
            if selectedSourceAccountId.isEmpty, let first = availableAccounts.first {
                selectedSourceAccountId = first.id
            }
            // Pre-select the previously-used category for this loan when available;
            // skip the technical `Loan Payment` value (handled by `category == nil`).
            if selectedCategory == nil,
               let candidate = initialCategory,
               candidate != TransactionType.loanPaymentCategoryName,
               availableCategories.contains(candidate) {
                selectedCategory = candidate
            }
        }
        .sheet(isPresented: $showingSubcategorySearch) {
            if let categoriesVM = categoriesViewModel,
               let categoryId = selectedCategoryId {
                SubcategorySearchView(
                    categoriesViewModel: categoriesVM,
                    categoryId: categoryId,
                    selectedSubcategoryIds: $selectedSubcategoryIds,
                    searchText: $subcategorySearchText
                )
                .onAppear { subcategorySearchText = "" }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            await Task.yield()
            isAmountFocused = true
        }
    }

    private var isFormValid: Bool {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else { return false }
        return !selectedSourceAccountId.isEmpty
    }

    private func savePayment() {
        guard let amount = AmountFormatter.parse(amountText), amount > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.invalidAmount", defaultValue: "Enter a valid amount")
            }
            HapticManager.error()
            return
        }
        guard !selectedSourceAccountId.isEmpty else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "loan.error.noSourceAccount", defaultValue: "Select a source account")
            }
            HapticManager.error()
            return
        }
        validationError = nil

        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote = trimmedNote.isEmpty ? nil : trimmedNote
        let result = LoanPaymentFormResult(
            amount: amount,
            date: dateStr,
            sourceAccountId: selectedSourceAccountId,
            note: resolvedNote,
            category: selectedCategory,
            subcategoryIds: selectedSubcategoryIds
        )
        onPayment(result)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Loan Payment") {
    let sampleLoanAccount = Account(
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

    let sourceAccount = Account(
        id: "source-1",
        name: "Kaspi Gold",
        currency: "KZT",
        initialBalance: 500_000
    )

    LoanPaymentView(
        account: sampleLoanAccount,
        loanInfo: sampleLoanAccount.loanInfo!,
        availableAccounts: [sourceAccount],
        onPayment: { _ in }
    )
}
