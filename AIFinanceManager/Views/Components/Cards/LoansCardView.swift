//
//  LoansCardView.swift
//  AIFinanceManager
//
//  Summary card for Home screen showing total debt,
//  monthly payment, and active loans count.
//

import SwiftUI

struct LoansCardView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel

    private var loans: [Account] {
        loansViewModel.loans
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "loan.listTitle", defaultValue: "Loans"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)

                if loans.isEmpty {
                    EmptyStateView(
                        title: String(
                            localized: "loan.emptyTitle",
                            defaultValue: "No Loans"
                        ),
                        style: .compact
                    )
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        FormattedAmountText(
                            amount: totalDebt,
                            currency: baseCurrency,
                            fontSize: AppTypography.h2,
                            fontWeight: .bold,
                            color: AppColors.textPrimary
                        )

                        Text(String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), loans.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !loans.isEmpty {
                loanIcons
            }
        }
        .animation(AppAnimation.gentleSpring, value: loans.isEmpty)
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Computed

    private var totalDebt: Double {
        loans.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
            .toDouble()
    }

    // MARK: - Icons

    private var loanIcons: some View {
        PackedCircleIconsView(
            items: loans.map { loan in
                PackedCircleItem(
                    id: loan.id,
                    iconSource: loan.iconSource,
                    amount: loan.loanInfo.map { ($0.remainingPrincipal as NSDecimalNumber).doubleValue } ?? 0
                )
            }
        )
    }
}

// MARK: - Decimal Helper

private extension Decimal {
    func toDouble() -> Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Previews

#Preview("Loans Card") {
    let coordinator = AppCoordinator()

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}

#Preview("Loans Card - Empty") {
    let coordinator = AppCoordinator()

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}
