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
        total > 0 ? (expenseAmount / total) : 0.0
    }
    
    private var incomePercent: Double {
        total > 0 ? (incomeAmount / total) : 0.0
    }
    
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Progress bar
            HStack(spacing: AppSpacing.xs) {
                if expensePercent > 0 {
                    Rectangle()
                        .foregroundStyle(Color.red)
                        .clipShape(.rect(cornerRadius: AppRadius.sm))
                        .shadow(color: Color.red.opacity(0.3), radius: 8)
                        .containerRelativeFrame(.horizontal) { width, _ in width * expensePercent }
                }
                if incomePercent > 0 {
                    Rectangle()
                        .foregroundStyle(Color.green)
                        .clipShape(.rect(cornerRadius: AppRadius.sm))
                        .shadow(color: Color.green.opacity(0.3), radius: 8)
                        .containerRelativeFrame(.horizontal) { width, _ in width * incomePercent }
                }
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
