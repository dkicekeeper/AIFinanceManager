//
//  TransactionCard.swift
//  AIFinanceManager
//
//  Reusable transaction card component for displaying transactions in lists
//

import SwiftUI

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    let customCategories: [CustomCategory]
    let accounts: [Account]
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?

    @State private var showingStopRecurringConfirmation = false
    @State private var showingEditModal = false

    // Кеш для style helper - вычисляется один раз
    private var styleHelper: CategoryStyleHelper {
        CategoryStyleHelper(category: transaction.category, type: transaction.type, customCategories: customCategories)
    }

    init(transaction: Transaction, currency: String, customCategories: [CustomCategory], accounts: [Account], viewModel: TransactionsViewModel? = nil, categoriesViewModel: CategoriesViewModel? = nil) {
        self.transaction = transaction
        self.currency = currency
        self.customCategories = customCategories
        self.accounts = accounts
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
    }
    
    private var isFutureDate: Bool {
        let dateFormatter = DateFormatters.dateFormatter
        guard let transactionDate = dateFormatter.date(from: transaction.date) else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        // Транзакция с будущей датой (дата > today)
        return transactionDate > today
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Transaction icon
            TransactionIconView(transaction: transaction, styleHelper: styleHelper)
            
            // Transaction info
            TransactionInfoView(
                transaction: transaction,
                accounts: accounts,
                linkedSubcategories: categoriesViewModel?.getSubcategoriesForTransaction(transaction.id) ?? []
            )
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if transaction.type == .internalTransfer {
                    transferAmountView
                } else {
                    Text(amountText)
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(amountColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .opacity(isFutureDate ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "accessibility.swipeForOptions"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Удаление
            Button(role: .destructive) {
                HapticManager.warning()
                if let viewModel = viewModel {
                    viewModel.deleteTransaction(transaction)
                }
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
            .accessibilityLabel(String(localized: "accessibility.deleteTransaction"))

            // Управление recurring (если есть)
            if transaction.recurringSeriesId != nil {
                Button {
                    showingStopRecurringConfirmation = true
                } label: {
                    Label(String(localized: "transaction.recurring"), systemImage: "arrow.clockwise")
                }
                .tint(.blue)
                .accessibilityLabel(String(localized: "accessibility.stopRecurring"))
            }
        }
        .alert(String(localized: "transaction.stopRecurring.title"), isPresented: $showingStopRecurringConfirmation) {
            Button(String(localized: "transaction.stopRecurring.cancel"), role: .cancel) {}
            Button(String(localized: "transaction.stopRecurring.confirm"), role: .destructive) {
                HapticManager.warning()
                if let viewModel = viewModel, let seriesId = transaction.recurringSeriesId {
                    viewModel.stopRecurringSeriesAndCleanup(seriesId: seriesId, transactionDate: transaction.date)
                }
            }
        } message: {
            Text(String(localized: "transaction.stopRecurring.message"))
        }
        .onTapGesture {
            showingEditModal = true
        }
        .sheet(isPresented: $showingEditModal) {
            if let viewModel = viewModel, let categoriesViewModel = categoriesViewModel {
                EditTransactionView(
                    transaction: transaction,
                    transactionsViewModel: viewModel,
                    categoriesViewModel: categoriesViewModel,
                    accounts: accounts,
                    customCategories: customCategories
                )
            }
        }
    }
    
    private var amountText: String {
        let prefix: String
        switch transaction.type {
        case .income:
            prefix = "+"
        case .expense:
            prefix = "-"
        case .internalTransfer:
            prefix = "" // Для переводов без префикса
        case .depositTopUp, .depositInterestAccrual:
            prefix = "+"
        case .depositWithdrawal:
            prefix = "-"
        }
        let mainAmount = Formatting.formatCurrency(transaction.amount, currency: transaction.currency)
        
        // Для переводов: показываем суммы для обоих счетов друг под другом
        if transaction.type == .internalTransfer {
            var lines: [String] = []
            
            // Получаем информацию о счетах
            var sourceAccount: Account? = nil
            var targetAccount: Account? = nil
            
            if let sourceId = transaction.accountId {
                sourceAccount = accounts.first(where: { $0.id == sourceId })
            }
            if let targetId = transaction.targetAccountId {
                targetAccount = accounts.first(where: { $0.id == targetId })
            }
            
            // Если счетов нет, показываем только основную сумму
            guard let source = sourceAccount else {
                return mainAmount
            }
            
            // Сумма для источника — из данных, записанных при создании
            let sourceCurrency = source.currency
            let sourceAmount = transaction.convertedAmount ?? transaction.amount

            if let target = targetAccount {
                let targetCurrency = target.currency

                if sourceCurrency == targetCurrency {
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                } else {
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                    // Сумма для получателя — из targetAmount, записанного при создании
                    let resolvedTargetAmount = transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount
                    let resolvedTargetCurrency = transaction.targetCurrency ?? targetCurrency
                    lines.append(Formatting.formatCurrency(resolvedTargetAmount, currency: resolvedTargetCurrency))
                }
            } else {
                lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
            }
            
            // Объединяем все строки через \n (суммы друг под другом, без скобок)
            return lines.isEmpty ? mainAmount : lines.joined(separator: "\n")
        }
        
        // Для доходов и расходов: проверяем наличие targetCurrency/targetAmount (из CSV или ручного ввода)
        if let targetCurrency = transaction.targetCurrency,
           let targetAmount = transaction.targetAmount,
           targetCurrency != transaction.currency {
            let targetText = Formatting.formatCurrency(targetAmount, currency: targetCurrency)
            return "\(prefix)\(mainAmount)\n(\(targetText))"
        }

        // Fallback: если есть конвертированная сумма и она отличается от основной
        if let convertedAmount = transaction.convertedAmount,
           let accountId = transaction.accountId,
           let account = accounts.first(where: { $0.id == accountId }),
           transaction.currency != account.currency {
            let convertedText = Formatting.formatCurrency(convertedAmount, currency: account.currency)
            return "\(prefix)\(mainAmount)\n(\(convertedText))"
        }

        return prefix + mainAmount
    }
    
    private var accessibilityText: String {
        let typeText: String
        switch transaction.type {
        case .income:
            typeText = String(localized: "transactionType.income")
        case .expense:
            typeText = String(localized: "transactionType.expense")
        case .internalTransfer:
            typeText = String(localized: "transactionType.transfer")
        default:
            typeText = String(localized: "transactionType.transfer")
        }
        
        let amountText = Formatting.formatCurrency(transaction.amount, currency: transaction.currency)
        var text = "\(typeText), \(transaction.category), \(amountText)"

        if transaction.type == .internalTransfer {
            // Для переводов: указываем источник и получателя
            if let sourceId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                text += ", from \(sourceAccount.name)"
            }
            if let targetId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetId }) {
                text += ", to \(targetAccount.name)"
            }
        } else {
            // Для доходов и расходов: указываем счет
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                text += ", from \(account.name)"
            }
        }

        if !transaction.description.isEmpty {
            text += ", \(transaction.description)"
        }

        if transaction.recurringSeriesId != nil {
            text += ", \(String(localized: "transaction.recurring"))"
        }

        return text
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return .green
        case .expense:
            return .primary
        case .internalTransfer:
            return .primary // Синий цвет для переводов для консистентности с иконкой
        case .depositTopUp, .depositInterestAccrual:
            return .green
        case .depositWithdrawal:
            return .primary
        }
    }
    
    @ViewBuilder
    private var transferAmountView: some View {
        // Получаем информацию о счетах
        let sourceAccount: Account? = transaction.accountId.flatMap { sourceId in
            accounts.first(where: { $0.id == sourceId })
        }
        let targetAccount: Account? = transaction.targetAccountId.flatMap { targetId in
            accounts.first(where: { $0.id == targetId })
        }
        
        if let source = sourceAccount {
            let sourceCurrency = source.currency
            // Сумма источника — из данных, записанных при создании
            let sourceAmount = transaction.convertedAmount ?? transaction.amount

            if let target = targetAccount {
                let targetCurrency = transaction.targetCurrency ?? target.currency
                // Сумма получателя — из targetAmount, записанного при создании
                let targetAmount = transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)

                    Text("+\(Formatting.formatCurrency(targetAmount, currency: targetCurrency))")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            } else {
                Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }
        } else {
            // Если счета источника нет, показываем основную сумму
            Text(amountText)
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(amountColor)
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let dateFormatter = DateFormatters.dateFormatter
    let sampleTransaction = Transaction(
        id: "test",
        date: dateFormatter.string(from: Date()),
        description: "Test transaction",
        amount: 1000,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? ""
    )
    
    return List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            customCategories: coordinator.categoriesViewModel.customCategories,
            accounts: coordinator.accountsViewModel.accounts,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
    .listStyle(PlainListStyle())
}
