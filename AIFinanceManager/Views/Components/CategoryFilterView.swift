//
//  CategoryFilterView.swift
//  AIFinanceManager
//
//  Reusable category filter component for HistoryView
//

import SwiftUI

struct CategoryFilterView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedExpenseCategories: Set<String> = []
    @State private var selectedIncomeCategories: Set<String> = []
    
    var body: some View {
        NavigationView {
            Form {
                // Опция "Все категории"
                Section {
                    HStack {
                        Text(String(localized: "categoryFilter.allCategories"))
                            .fontWeight(.medium)
                        Spacer()
                        if viewModel.selectedCategories == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.selection()
                        selectedExpenseCategories.removeAll()
                        selectedIncomeCategories.removeAll()
                        viewModel.selectedCategories = nil
                    }
                }
                
                // Категории расходов
                Section(header: Text(String(localized: "transactionType.expense"))) {
                    if viewModel.expenseCategories.isEmpty {
                        Text(String(localized: "categoryFilter.noExpenseCategories"))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.expenseCategories, id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                if selectedExpenseCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.selection()
                                if selectedExpenseCategories.contains(category) {
                                    selectedExpenseCategories.remove(category)
                                } else {
                                    selectedExpenseCategories.insert(category)
                                }
                            }
                        }
                    }
                }
                
                // Категории доходов
                Section(header: Text(String(localized: "transactionType.income"))) {
                    if viewModel.incomeCategories.isEmpty {
                        Text(String(localized: "categoryFilter.noIncomeCategories"))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.incomeCategories, id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                if selectedIncomeCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.selection()
                                if selectedIncomeCategories.contains(category) {
                                    selectedIncomeCategories.remove(category)
                                } else {
                                    selectedIncomeCategories.insert(category)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "navigation.categoryFilter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.success()
                        applyFilter()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                // Загружаем текущий фильтр
                if let currentFilter = viewModel.selectedCategories {
                    selectedExpenseCategories = Set(viewModel.expenseCategories.filter { currentFilter.contains($0) })
                    selectedIncomeCategories = Set(viewModel.incomeCategories.filter { currentFilter.contains($0) })
                }
            }
        }
    }
    
    private func applyFilter() {
        let allSelected = selectedExpenseCategories.union(selectedIncomeCategories)
        if allSelected.isEmpty {
            // Если ничего не выбрано, показываем все категории
            viewModel.selectedCategories = nil
        } else {
            viewModel.selectedCategories = allSelected
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    CategoryFilterView(viewModel: coordinator.transactionsViewModel)
}
