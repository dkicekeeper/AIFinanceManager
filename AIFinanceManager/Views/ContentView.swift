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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.allTransactions.isEmpty {
                        summaryCards
                    }

                    QuickAddTransactionView(viewModel: viewModel)

                    if viewModel.isLoading {
                        ProgressView("Analyzing PDF...")
                            .padding()
                    }
                    
                    if let error = viewModel.errorMessage {
                        ErrorMessageView(message: error)
                    }

                    transactionsSection
                }
                .padding()
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
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "doc.badge.plus")
                    }
                }
            }
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
            Text("Transactions")
                .font(.title2)
                .fontWeight(.bold)
            
            TransactionsTableView(viewModel: viewModel)
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
                .font(.title2)
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
