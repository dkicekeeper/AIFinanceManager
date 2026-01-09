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
    @State private var showingAccountsManagement = false
    @State private var showingCategoriesManagement = false
    @State private var recognizedTransactions: [Transaction]?
    @State private var showingTransactionPreview = false
    @State private var showingResetConfirmation = false
    @State private var showingVoiceInput = false
    @State private var showingVoiceConfirmation = false
    @State private var parsedOperation: ParsedOperation?
    @StateObject private var voiceService = VoiceInputService()
    
    var body: some View {
        NavigationView {
            ScrollView {
            VStack(spacing: 16) {
                accountsSection
                    .padding(.horizontal)

                if !viewModel.allTransactions.isEmpty {
                    NavigationLink(destination: HistoryView(viewModel: viewModel, initialCategory: nil)) {
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
            .sheet(isPresented: $showingTransactionPreview) {
                if let transactions = recognizedTransactions {
                    TransactionPreviewView(viewModel: viewModel, transactions: transactions)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingCategoriesManagement = true }) {
                            Image(systemName: "tag")
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "doc.badge.plus")
                        }
                        
                        Menu {
                            Button(role: .destructive, action: {
                                showingResetConfirmation = true
                            }) {
                                Label("Обнулить все данные", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Обнулить все данные?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Обнулить", role: .destructive) {
                    viewModel.resetAllData()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие удалит все транзакции, счета, категории и другие данные. Это действие нельзя отменить.")
            }
            .sheet(isPresented: $showingAccountsManagement) {
                AccountsManagementView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingCategoriesManagement) {
                CategoriesManagementView(viewModel: viewModel)
            }
            .sheet(item: $selectedAccount) { account in
                AccountActionView(viewModel: viewModel, account: account)
            }
            .sheet(isPresented: $showingVoiceInput) {
                VoiceInputView(voiceService: voiceService) { transcribedText in
                    showingVoiceInput = false
                    // Парсим текст синхронно
                    let parser = VoiceInputParser(
                        accounts: viewModel.accounts,
                        categories: viewModel.customCategories,
                        subcategories: viewModel.subcategories,
                        defaultAccount: viewModel.accounts.first
                    )
                    let parsed = parser.parse(transcribedText)
                    // Устанавливаем parsedOperation синхронно перед открытием sheet
                    parsedOperation = parsed
                    // Открываем sheet сразу после установки parsedOperation
                    showingVoiceConfirmation = true
                }
            }
            .sheet(isPresented: $showingVoiceConfirmation) {
                if let parsed = parsedOperation {
                    VoiceInputConfirmationView(
                        viewModel: viewModel,
                        parsedOperation: parsed,
                        originalText: voiceService.getFinalText()
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Кнопка микрофона
                Button(action: {
                    showingVoiceInput = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 68, height: 68)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
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
                                HStack(spacing: 8) {
                                    account.bankLogo.image(size: 32)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name)
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                        Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
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
            
            Button(action: { showingAccountsManagement = true }) {
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
            
            // В планах
            if summary.plannedAmount > 0 {
                HStack {
                    Text("В планах")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(Formatting.formatCurrency(summary.plannedAmount, currency: currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
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
            
            // Проверяем, что текст не пустой
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                viewModel.errorMessage = "Не удалось извлечь текст из PDF. Убедитесь, что файл содержит текст (не сканированное изображение)."
                viewModel.isLoading = false
                return
            }
            
            let result = try await GeminiService.shared.analyzeTransactions(from: text)
            
            // Проверяем, что есть транзакции
            guard !result.transactions.isEmpty else {
                viewModel.errorMessage = "Не удалось распознать транзакции в выписке. Попробуйте другой файл."
                viewModel.isLoading = false
                return
            }
            
            // Сохраняем распознанные транзакции для предпросмотра
            recognizedTransactions = result.transactions
            showingTransactionPreview = true
        } catch let error as GeminiError {
            viewModel.errorMessage = error.localizedDescription
        } catch let error as PDFError {
            viewModel.errorMessage = error.localizedDescription
        } catch {
            viewModel.errorMessage = "Ошибка: \(error.localizedDescription)"
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
