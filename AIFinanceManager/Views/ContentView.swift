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
    @State private var showAllTransactions = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if !viewModel.accounts.isEmpty {
                    accountsSection
                        .padding(.horizontal)
                }

                if !viewModel.allTransactions.isEmpty {
                    summaryCards
                        .padding(.horizontal)
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

                // История операций со своей прокруткой
                NavigationLink(destination: HistoryView(viewModel: viewModel)) {
                    transactionsSection
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical)
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
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "doc.badge.plus")
                    }
                }
            }
        }
    }
    
    private var accountsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.accounts) { account in
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
            }
            .padding(.vertical, 4)
        }
    }
    private var summaryCards: some View {
        let summary = viewModel.summary
        let currency = viewModel.allTransactions.first?.currency ?? "USD"

        return HStack(spacing: 12) {
            SummaryCard(title: "Income", amount: summary.totalIncome, currency: currency, color: .green)
            SummaryCard(title: "Expenses", amount: summary.totalExpenses, currency: currency, color: .red)
            SummaryCard(
                title: "Net Flow",
                amount: summary.netFlow,
                currency: currency,
                color: summary.netFlow >= 0 ? .green : .red
            )
        }
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transactions")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !viewModel.filteredTransactions.isEmpty {
                    Button(showAllTransactions ? "Hide" : "Show all") {
                        showAllTransactions.toggle()
                    }
                    .font(.caption)
                }
            }
            
            TransactionsTableView(
                viewModel: viewModel,
                limit: showAllTransactions ? nil : 3
            )
        }
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
