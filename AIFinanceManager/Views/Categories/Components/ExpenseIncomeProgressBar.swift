//
//  ExpenseIncomeProgressBar.swift
//  AIFinanceManager
//
//  Progress bar component showing expense and income amounts
//

import SwiftUI

struct ExpenseIncomeProgressBar: View {
    let expenseAmount: Double
    let incomeAmount: Double
    let currency: String
    
    private var total: Double {
        expenseAmount + incomeAmount
    }
    
    private var expensePercent: Double {
        total > 0 ? max(0, min(1, expenseAmount / total)) : 0.0
    }

    private var incomePercent: Double {
        total > 0 ? max(0, min(1, incomeAmount / total)) : 0.0
    }
    
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Progress bar
            GeometryReader { geometry in
                HStack(spacing: AppSpacing.xs) {
                    if expensePercent > 0 {
                        Rectangle()
                            .foregroundStyle(AppColors.destructive)
                            .frame(width: geometry.size.width * expensePercent)
                            .clipShape(.rect(cornerRadius: AppRadius.sm))
                            .shadow(color: AppColors.destructive.opacity(0.3), radius: 8)
                    }
                    if incomePercent > 0 {
                        Rectangle()
                            .foregroundStyle(AppColors.income)
                            .frame(width: geometry.size.width * incomePercent)
                            .clipShape(.rect(cornerRadius: AppRadius.sm))
                            .shadow(color: AppColors.income.opacity(0.3), radius: 8)
                    }
                }
                .clipped()
            }
            .frame(height: AppSpacing.md)
            
            // Amounts below progress bar
            HStack {
                FormattedAmountText(
                    amount: expenseAmount,
                    currency: currency,
                    fontSize: AppTypography.h4,
                    fontWeight: .semibold,
                    color: AppColors.textPrimary
                )

                Spacer()

                FormattedAmountText(
                    amount: incomeAmount,
                    currency: currency,
                    fontSize: AppTypography.h4,
                    fontWeight: .semibold,
                    color: AppColors.income
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.lg) {
        ExpenseIncomeProgressBar(
            expenseAmount: 5000,
            incomeAmount: 10000,
            currency: "KZT"
        )
        
        ExpenseIncomeProgressBar(
            expenseAmount: 10000,
            incomeAmount: 5000,
            currency: "USD"
        )
    }
    .padding()
}
