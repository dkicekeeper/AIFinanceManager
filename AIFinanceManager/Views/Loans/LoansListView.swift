//
//  LoansListView.swift
//  AIFinanceManager
//
//  List view displaying all loans and installments with progress,
//  next payment info, and navigation to detail/edit views.
//

import SwiftUI

struct LoansListView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel
    let balanceCoordinator: BalanceCoordinator
    @Environment(AppCoordinator.self) private var appCoordinator

    @State private var showingAddLoan = false
    @State private var selectedFilter: LoanFilter = .all

    enum LoanFilter: String, CaseIterable {
        case all
        case credits
        case installments

        var label: String {
            switch self {
            case .all: return String(localized: "loan.filterAll", defaultValue: "All")
            case .credits: return String(localized: "loan.filterCredits", defaultValue: "Credits")
            case .installments: return String(localized: "loan.filterInstallments", defaultValue: "Installments")
            }
        }
    }

    private var filteredLoans: [Account] {
        switch selectedFilter {
        case .all: return loansViewModel.loans
        case .credits: return loansViewModel.loans.filter { $0.loanInfo?.loanType == .annuity }
        case .installments: return loansViewModel.loans.filter { $0.loanInfo?.loanType == .installment }
        }
    }

    var body: some View {
        Group {
            if loansViewModel.loans.isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: String(localized: "loan.emptyTitle", defaultValue: "No Loans"),
                    description: String(localized: "loan.emptyDescription", defaultValue: "Add your credits and installments to track payments and progress")
                )
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        // Summary card
                        loansSummary
                            .screenPadding()

                        // Filter
                        if hasMultipleTypes {
                            Picker(String(localized: "loan.filter", defaultValue: "Filter"), selection: $selectedFilter) {
                                ForEach(LoanFilter.allCases, id: \.self) { filter in
                                    Text(filter.label).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .screenPadding()
                        }

                        // Loan cards
                        ForEach(filteredLoans) { loan in
                            NavigationLink(value: HomeDestination.loanDetail(loan.id)) {
                                loanCard(loan)
                            }
                            .buttonStyle(.plain)
                            .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "loan.listTitle", defaultValue: "Loans"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.light()
                    showingAddLoan = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddLoan) {
            LoanEditView(
                loansViewModel: loansViewModel,
                account: nil,
                onSave: { newAccount in
                    loansViewModel.addLoanAccount(newAccount)
                    showingAddLoan = false
                }
            )
        }
    }

    // MARK: - Summary

    private var loansSummary: some View {
        let totalDebt = loansViewModel.loans.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
        let totalMonthlyPayment = loansViewModel.loans.compactMap { $0.loanInfo?.monthlyPayment }
            .reduce(Decimal(0), +)
        let primaryCurrency = loansViewModel.loans.first?.currency ?? "KZT"

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(String(localized: "loan.totalDebt", defaultValue: "Total Debt"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: totalDebt).doubleValue,
                        currency: primaryCurrency,
                        fontSize: AppTypography.h2
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(String(localized: "loan.monthlyTotal", defaultValue: "Monthly"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: totalMonthlyPayment).doubleValue,
                        currency: primaryCurrency,
                        fontSize: AppTypography.h4,
                        color: AppColors.expense
                    )
                }
            }

            Text(String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), loansViewModel.loans.count))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    // MARK: - Loan Card

    private func loanCard(_ loan: Account) -> some View {
        guard let loanInfo = loan.loanInfo else { return AnyView(EmptyView()) }

        let progress = LoanPaymentService.progressPercentage(loanInfo: loanInfo)
        let nextDate = LoanPaymentService.nextPaymentDate(loanInfo: loanInfo)
        let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)

        return AnyView(
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header: icon + name + bank + type badge
                HStack {
                    IconView(source: loan.iconSource, size: AppIconSize.lg)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.name)
                            .font(AppTypography.bodyEmphasis)
                        Text(loanInfo.bankName)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(loanInfo.loanType == .annuity
                         ? String(localized: "loan.typeAnnuityShort", defaultValue: "Credit")
                         : String(localized: "loan.typeInstallmentShort", defaultValue: "Installment"))
                        .font(AppTypography.caption)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(loanInfo.loanType == .annuity ? AppColors.expense.opacity(0.15) : AppColors.planned.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Progress
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue, currency: loan.currency))
                            .font(AppTypography.bodySmall)
                        Text(String(localized: "loan.of", defaultValue: "of"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                        Text(Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue, currency: loan.currency))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.income)
                    }
                    ProgressView(value: progress)
                        .tint(AppColors.income)
                }

                // Footer: next payment + remaining
                HStack {
                    if let nextDate = nextDate {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "calendar")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                            Text(DateFormatters.displayDateFormatter.string(from: nextDate))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(String(format: String(localized: "loan.remainingShort", defaultValue: "%d left"), remaining))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        )
    }

    private var hasMultipleTypes: Bool {
        let types = Set(loansViewModel.loans.compactMap { $0.loanInfo?.loanType })
        return types.count > 1
    }
}
