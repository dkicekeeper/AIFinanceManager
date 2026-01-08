//
//  ContentView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import PDFKit

struct ContentView: View {
    @StateObject private var viewModel = TransactionsViewModel()
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var selectedAccount: Account?
    
    var body: some View {
        NavigationView {
            ScrollView {
            VStack(spacing: 16) {
                accountsSection
                    .padding(.horizontal)

                if !viewModel.allTransactions.isEmpty {
                    NavigationLink(destination: HistoryView(viewModel: viewModel)) {
                        analyticsCard
                            .padding(.horizontal)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                QuickAddTransactionView(viewModel: viewModel)
                    .padding(.horizontal)

                if viewModel.isLoading {
                    ProgressView("Analyzing PDF...")
                        .padding()
                }
                
                if let error = viewModel.errorMessage {
                    ErrorMessageView(message: error)
                        .padding(.horizontal)
                }
            }
                .padding(.vertical)
            }
            .navigationTitle("AI Finance Manager")
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    selectedFileURL = url
                    Task {
                        await analyzePDF(url: url)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: CategoriesManagementView(viewModel: viewModel)) {
                            Image(systemName: "tag")
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                }
            }
            .sheet(item: $selectedAccount) { account in
                AccountActionView(viewModel: viewModel, account: account)
            }
        }
    }
    
    private var accountsSection: some View {
        HStack {
            if viewModel.accounts.isEmpty {
                Text("Нет счетов")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.accounts) { account in
                            Button(action: {
                                selectedAccount = account
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .padding(10)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            NavigationLink(destination: AccountsManagementView(viewModel: viewModel)) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
    }
    private var analyticsCard: some View {
        let summary = viewModel.summary
        let currency = viewModel.allTransactions.first?.currency ?? "USD"
        let total = summary.totalExpenses + summary.totalIncome
        let expensePercent = total > 0 ? (summary.totalExpenses / total) : 0.0
        let incomePercent = total > 0 ? (summary.totalIncome / total) : 0.0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Суммы сверху
            HStack {
                Text(Formatting.formatCurrency(summary.totalExpenses, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text(Formatting.formatCurrency(summary.totalIncome, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            
            // Одна полоса, где расходы и доходы толкают друг друга
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Расходы слева
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * expensePercent)
                    
                    // Доходы справа
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * incomePercent)
                    
                    // Пустое пространство
                    Spacer()
                }
                .cornerRadius(4)
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    
    private func analyzePDF(url: URL) async {
        viewModel.isLoading = true
        viewModel.errorMessage = nil
        
        do {
            let text = try await PDFService.shared.extractText(from: url)
            let result = try await GeminiService.shared.analyzeTransactions(from: text)
            viewModel.addTransactions(result.transactions)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
        
        viewModel.isLoading = false
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(Formatting.formatCurrency(amount, currency: currency))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ErrorMessageView: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .foregroundColor(.red)
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
