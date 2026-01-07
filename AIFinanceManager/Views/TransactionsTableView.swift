//
//  TransactionsTableView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct TransactionsTableView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    
    var body: some View {
        if viewModel.filteredTransactions.isEmpty {
            Text("No transactions found")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List {
                ForEach(viewModel.filteredTransactions) { transaction in
                    TransactionRow(
                        transaction: transaction,
                        currency: viewModel.allTransactions.first?.currency ?? "USD",
                        uniqueCategories: viewModel.uniqueCategories,
                        onUpdateCategory: { category, subcategory in
                            viewModel.updateTransactionCategory(transaction.id, category: category, subcategory: subcategory)
                        }
                    )
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let currency: String
    let uniqueCategories: [String]
    let onUpdateCategory: (String, String?) -> Void
    
    @State private var isEditingCategory = false
    @State private var categoryText = ""
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatting.formatDate(transaction.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(transaction.description)
                    .font(.body)
                
                if isEditingCategory {
                    TextField("Category", text: $categoryText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            saveCategory()
                        }
                } else {
                    Button(action: { startEditing() }) {
                        HStack {
                            Text(transaction.category)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(CategoryColors.hexColor(for: transaction.category, opacity: 0.2))
                                .foregroundColor(CategoryColors.hexColor(for: transaction.category))
                                .cornerRadius(8)
                            
                            if let subcategory = transaction.subcategory {
                                Text(subcategory)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            Text(amountText)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(amountColor)
        }
        .padding(.vertical, 4)
    }
    
    private var amountText: String {
        let prefix = transaction.type == .income ? "+" : transaction.type == .expense ? "-" : ""
        return prefix + Formatting.formatCurrency(transaction.amount, currency: currency)
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return .green
        case .expense:
            return .red
        case .internalTransfer:
            return .gray
        }
    }
    
    private func startEditing() {
        categoryText = transaction.subcategory != nil
            ? "\(transaction.category):\(transaction.subcategory!)"
            : transaction.category
        isEditingCategory = true
    }
    
    private func saveCategory() {
        let parts = categoryText.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        let category = parts.first ?? transaction.category
        let subcategory = parts.count > 1 ? parts[1] : nil
        onUpdateCategory(category, subcategory)
        isEditingCategory = false
    }
}

#Preview {
    TransactionsTableView(viewModel: TransactionsViewModel())
}
