//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var selectedTimeFilter: TimeFilter = .week
    @State private var selectedAccountFilter: String? = nil // nil = все счета
    @State private var searchText = ""
    
    enum TimeFilter: String, CaseIterable {
        case day = "За день"
        case week = "За неделю"
        case month = "За месяц"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Фильтры
            filterSection
            
            // Список транзакций
            transactionsList
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by amount, category, or description")
    }
    
    private var filterSection: some View {
        HStack(spacing: 12) {
            // Фильтр по времени - выпадающий список
            Menu {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Button(action: { selectedTimeFilter = filter }) {
                        HStack {
                            Text(filter.rawValue)
                            if selectedTimeFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedTimeFilter.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(20)
            }
            
            // Фильтр по счетам - выпадающий список
            Menu {
                Button(action: { selectedAccountFilter = nil }) {
                    HStack {
                        Text("Все счета")
                        if selectedAccountFilter == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(viewModel.accounts) { account in
                    Button(action: { selectedAccountFilter = account.id }) {
                        HStack {
                            Text(account.name)
                            if selectedAccountFilter == account.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedAccountFilter == nil ? "Все счета" : (viewModel.accounts.first(where: { $0.id == selectedAccountFilter })?.name ?? "Все счета"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(20)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
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
                    Section(header: dateHeader(for: dateKey, transactions: grouped[dateKey] ?? [])) {
                        ForEach(grouped[dateKey] ?? []) { transaction in
                            TransactionCard(
                                transaction: transaction,
                                currency: viewModel.allTransactions.first?.currency ?? "USD",
                                customCategories: viewModel.customCategories,
                                accounts: viewModel.accounts
                            )
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
        )
    }
    
    private var filteredTransactions: [Transaction] {
        var transactions = viewModel.filteredTransactions
        
        // Фильтр по счету
        if let accountId = selectedAccountFilter {
            transactions = transactions.filter { $0.accountId == accountId || $0.targetAccountId == accountId }
        }
        
        // Фильтр по времени
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        transactions = transactions.filter { transaction in
            guard let date = dateFormatter.date(from: transaction.date) else { return false }
            
            switch selectedTimeFilter {
            case .day:
                return calendar.isDate(date, inSameDayAs: now)
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return date >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return date >= monthAgo
            }
        }
        
        // Фильтр по поиску
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            transactions = transactions.filter { transaction in
                // Поиск по категории
                if transaction.category.lowercased().contains(searchLower) {
                    return true
                }
                // Поиск по описанию
                if transaction.description.lowercased().contains(searchLower) {
                    return true
                }
                // Поиск по сумме
                let amountString = String(format: "%.2f", transaction.amount)
                if amountString.contains(searchText) || searchText.contains(amountString) {
                    return true
                }
                // Поиск по сумме с валютой
                let currency = viewModel.allTransactions.first?.currency ?? "USD"
                let formattedAmount = Formatting.formatCurrency(transaction.amount, currency: currency).lowercased()
                if formattedAmount.contains(searchLower) {
                    return true
                }
                return false
            }
        }
        
        return transactions
    }
    
    private var groupedTransactions: [String: [Transaction]] {
        let transactions = filteredTransactions
        var grouped: [String: [Transaction]] = [:]
        
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for transaction in transactions {
            guard let date = dateFormatter.date(from: transaction.date) else { continue }
            
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
        
        // Сортируем транзакции внутри каждого дня по времени (если есть) или по дате
        // Сверху последние (новые), снизу первые (старые)
        for key in grouped.keys {
            grouped[key]?.sort { tx1, tx2 in
                if let time1 = tx1.time, let time2 = tx2.time {
                    return time1 > time2 // Новые сверху
                }
                return tx1.date > tx2.date // Новые сверху
            }
        }
        
        return grouped
    }
    
    private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
        let currency = viewModel.allTransactions.first?.currency ?? "USD"
        let dayExpenses = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
        
        return HStack {
            Text(dateKey)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            if dayExpenses > 0 {
                Text("-" + Formatting.formatCurrency(dayExpenses, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
        }
        .textCase(nil)
    }
}

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    let customCategories: [CustomCategory]
    let accounts: [Account]
    
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
                // Название категории
                Text(transaction.category)
                    .font(.body)
                    .fontWeight(.medium)
                
                // Счет
                if let accountId = transaction.accountId,
                   let account = accounts.first(where: { $0.id == accountId }) {
                    Text(account.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Время
                if let time = transaction.time {
                    Text(time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Описание (если есть)
                if !transaction.description.isEmpty {
                    Text(transaction.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            return CategoryColors.hexColor(for: transaction.category, opacity: 0.2, customCategories: customCategories)
        case .internalTransfer:
            return Color.blue.opacity(0.2)
        }
    }
    
    private var categoryEmoji: String {
        CategoryEmoji.emoji(for: transaction.category, type: transaction.type, customCategories: customCategories)
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
    NavigationView {
        HistoryView(viewModel: TransactionsViewModel())
    }
}
