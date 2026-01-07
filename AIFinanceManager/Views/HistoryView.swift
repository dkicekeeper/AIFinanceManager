//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var selectedFilter: HistoryFilter = .week
    @State private var showingSearch = false
    @State private var searchText = ""
    
    enum HistoryFilter: String, CaseIterable {
        case week = "За неделю"
        case all = "Все продукты"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Фильтры
            filterSection
            
            // Аналитика (если есть транзакции)
            if !viewModel.filteredTransactions.isEmpty {
                analyticsCard
                    .padding(.horizontal)
                    .padding(.top, 12)
            }
            
            // Список транзакций
            transactionsList
        }
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSearch.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView(viewModel: viewModel, searchText: $searchText)
        }
    }
    
    private var filterSection: some View {
        HStack(spacing: 12) {
            ForEach(HistoryFilter.allCases, id: \.self) { filter in
                Button(action: { selectedFilter = filter }) {
                    Text(filter.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedFilter == filter ? Color.blue : Color(.systemGray5))
                        .cornerRadius(20)
                }
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    private var analyticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Аналитика операций")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let summary = viewModel.summary
            let currency = viewModel.allTransactions.first?.currency ?? "USD"
            
            HStack(spacing: 16) {
                // Расходы
                VStack(alignment: .leading, spacing: 4) {
                    Text("Расходы")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 60, height: 8)
                            .cornerRadius(4)
                        
                        Text(Formatting.formatCurrency(summary.totalExpenses, currency: currency))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                
                // Доходы
                VStack(alignment: .leading, spacing: 4) {
                    Text("Доходы")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 60, height: 8)
                            .cornerRadius(4)
                        
                        Text(Formatting.formatCurrency(summary.totalIncome, currency: currency))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var transactionsList: some View {
        let grouped = groupedTransactions
        
        if grouped.isEmpty {
            return AnyView(
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Нет операций")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            )
        }
        
        return AnyView(
            List {
                ForEach(grouped.keys.sorted(by: >), id: \.self) { dateKey in
                    Section(header: dateHeader(for: dateKey)) {
                        ForEach(grouped[dateKey] ?? []) { transaction in
                            TransactionCard(transaction: transaction, currency: viewModel.allTransactions.first?.currency ?? "USD")
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
        )
    }
    
    private var groupedTransactions: [String: [Transaction]] {
        let transactions = viewModel.filteredTransactions
        var grouped: [String: [Transaction]] = [:]
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for transaction in transactions {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: transaction.date) else { continue }
            
            let dateKey: String
            if calendar.isDateInToday(date) {
                dateKey = "Сегодня"
            } else if calendar.isDateInYesterday(date) {
                dateKey = "Вчера"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.locale = Locale(identifier: "ru_RU")
                displayFormatter.dateFormat = "d MMMM"
                dateKey = displayFormatter.string(from: date)
            }
            
            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(transaction)
        }
        
        return grouped
    }
    
    private func dateHeader(for dateKey: String) -> some View {
        Text(dateKey)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .textCase(nil)
    }
}

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка категории
            Circle()
                .fill(categoryColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(categoryEmoji)
                        .font(.system(size: 20))
                )
            
            // Информация
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(transaction.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Сумма
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(amountColor)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var categoryColor: Color {
        switch transaction.type {
        case .income:
            return Color.green.opacity(0.2)
        case .expense:
            return CategoryColors.hexColor(for: transaction.category, opacity: 0.2)
        case .internalTransfer:
            return Color.blue.opacity(0.2)
        }
    }
    
    private var categoryEmoji: String {
        CategoryEmoji.emoji(for: transaction.category, type: transaction.type)
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

struct SearchView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Binding var searchText: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Поиск", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                // Здесь можно добавить фильтрованные результаты
                Spacer()
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        HistoryView(viewModel: TransactionsViewModel())
    }
}
