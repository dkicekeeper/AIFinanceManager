//
//  SetBudgetSheet.swift
//  AIFinanceManager
//
//  Sheet for setting or editing category budget
//

import SwiftUI

struct SetBudgetSheet: View {
    let category: CustomCategory
    @ObservedObject var viewModel: CategoriesViewModel
    @Binding var isPresented: Bool

    @State private var budgetAmount: String = ""
    @State private var selectedPeriod: CustomCategory.BudgetPeriod = .monthly
    @State private var resetDay: Int = 1

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(String(localized: "budget_amount"), text: $budgetAmount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(String(localized: "budget_amount"))

                    Picker(String(localized: "budget_period"), selection: $selectedPeriod) {
                        Text(String(localized: "weekly")).tag(CustomCategory.BudgetPeriod.weekly)
                        Text(String(localized: "monthly")).tag(CustomCategory.BudgetPeriod.monthly)
                        Text(String(localized: "yearly")).tag(CustomCategory.BudgetPeriod.yearly)
                    }
                    .accessibilityLabel(String(localized: "budget_period"))

                    if selectedPeriod == .monthly {
                        Stepper(
                            String(localized: "budget_reset_day") + " \(resetDay)",
                            value: $resetDay,
                            in: 1...31
                        )
                        .accessibilityLabel(String(localized: "budget_reset_day"))
                        .accessibilityValue("\(resetDay)")
                    }
                } header: {
                    Text(String(localized: "budget_settings"))
                } footer: {
                    if selectedPeriod == .monthly {
                        Text(String(localized: "budget_reset_day_description"))
                            .font(.caption)
                    }
                }

                // Current progress (if budget already exists)
                if let existingBudget = category.budgetAmount {
                    Section {
                        HStack {
                            Text(String(localized: "current_budget"))
                            Spacer()
                            Text("\(Int(existingBudget))₸")
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text(String(localized: "current_settings"))
                    }
                }

                // Remove budget button (if budget exists)
                if category.budgetAmount != nil {
                    Section {
                        Button(role: .destructive) {
                            viewModel.removeBudget(for: category.id)
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text(String(localized: "remove_budget"))
                            }
                        }
                        .accessibilityLabel(String(localized: "remove_budget"))
                    }
                }
            }
            .navigationTitle(String(localized: "set_budget_for") + " \(category.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {
                        saveBudget()
                    }
                    .disabled(budgetAmount.isEmpty || Double(budgetAmount) == nil || Double(budgetAmount)! <= 0)
                }
            }
        }
        .onAppear {
            // Pre-fill with existing budget values
            if let amount = category.budgetAmount {
                budgetAmount = String(Int(amount))
            }
            selectedPeriod = category.budgetPeriod
            resetDay = category.budgetResetDay
        }
    }

    private func saveBudget() {
        guard let amount = Double(budgetAmount), amount > 0 else { return }

        viewModel.setBudget(
            for: category.id,
            amount: amount,
            period: selectedPeriod,
            resetDay: resetDay
        )

        isPresented = false
    }
}

#Preview("Set Budget Sheet") {
    SetBudgetSheet(
        category: CustomCategory(
            name: "Food",
            iconName: "fork.knife",
            colorHex: "#FF6B6B",
            type: .expense
        ),
        viewModel: CategoriesViewModel(),
        isPresented: .constant(true)
    )
}
