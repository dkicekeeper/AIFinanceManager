//
//  TransactionsTableView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct TransactionsTableView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let limit: Int?
    
    var body: some View {
        let all = viewModel.filteredTransactions
        // Берем последние N операций (первые в отсортированном списке по дате)
        // Список уже отсортирован по убыванию даты, поэтому берем первые N
        let transactions = limit != nil ? Array(all.prefix(limit!)) : all
        
        if transactions.isEmpty {
            Text("No transactions found", comment: "No transactions message")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List {
                ForEach(transactions) { transaction in
                    TransactionRow(
                        transaction: transaction,
                        currency: viewModel.allTransactions.first?.currency ?? "USD",
                        uniqueCategories: viewModel.uniqueCategories,
                        customCategories: viewModel.customCategories,
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
    let customCategories: [CustomCategory]
    let onUpdateCategory: (String, String?) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let time = transaction.time {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(transaction.description)
                    .font(.body)
                
                    HStack {
                        Text(transaction.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CategoryColors.hexColor(for: transaction.category, opacity: 0.2, customCategories: customCategories))
                            .foregroundColor(CategoryColors.hexColor(for: transaction.category, customCategories: customCategories))
                            .cornerRadius(8)
                    
                    if let subcategory = transaction.subcategory {
                        Text(subcategory)
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
}

#Preview {
    TransactionsTableView(viewModel: TransactionsViewModel(), limit: nil)
}
