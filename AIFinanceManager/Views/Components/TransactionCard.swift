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
            // Удаление - для recurring транзакций просто удаляем операцию без диалога
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
                    // Note: stopRecurringSeries should be in SubscriptionsViewModel
                    // For now, keeping in TransactionsViewModel for backward compatibility
                    viewModel.stopRecurringSeries(seriesId)
                    // После остановки серии нужно удалить будущие транзакции и перегенерировать список
                    let dateFormatter = DateFormatters.dateFormatter
                    guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }
                    let today = Calendar.current.startOfDay(for: Date())
                    
                    // Удаляем все будущие транзакции этой серии (начиная со следующего дня после текущей транзакции)
                    // Note: recurringOccurrences should be accessed through SubscriptionsViewModel
                    let futureOccurrences = viewModel.recurringOccurrences.filter { occurrence in
                        guard occurrence.seriesId == seriesId,
                              let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                            return false
                        }
                        // Удаляем только будущие транзакции (после даты текущей транзакции)
                        return occurrenceDate > transactionDate && occurrenceDate > today
                    }
                    
                    for occurrence in futureOccurrences {
                        viewModel.allTransactions.removeAll { $0.id == occurrence.transactionId }
                        viewModel.recurringOccurrences.removeAll { $0.id == occurrence.id }
                    }
                    
                    viewModel.recalculateAccountBalances()
                    viewModel.saveToStorage()
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
            
            // Сумма для источника
            var sourceAmount: Double = transaction.amount
            var sourceCurrency: String = transaction.currency
            
            sourceCurrency = source.currency
            if transaction.currency == source.currency {
                // Валюты совпадают - используем сумму как есть
                sourceAmount = transaction.amount
            } else if let convertedAmount = transaction.convertedAmount {
                // Есть конвертированная сумма для источника
                sourceAmount = convertedAmount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: source.currency
            ) {
                // Конвертируем на лету
                sourceAmount = converted
            }
            
            // Если есть счет получателя и валюта отличается от источника - показываем обе суммы
            if let target = targetAccount {
                let targetCurrency = target.currency
                
                // Если валюты источника и получателя одинаковые - показываем только сумму источника
                if sourceCurrency == targetCurrency {
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                } else {
                    // Валюты разные - показываем обе суммы
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                    
                    var targetAmount: Double = transaction.amount
                    if transaction.currency == targetCurrency {
                        // Валюты совпадают - используем сумму как есть
                        targetAmount = transaction.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: transaction.amount,
                        from: transaction.currency,
                        to: targetCurrency
                    ) {
                        // Валюты разные - конвертируем на лету через кэш
                        targetAmount = converted
                    }
                    lines.append(Formatting.formatCurrency(targetAmount, currency: targetCurrency))
                }
            } else {
                // Если счета получателя нет, показываем только сумму источника
                lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
            }
            
            // Объединяем все строки через \n (суммы друг под другом, без скобок)
            return lines.isEmpty ? mainAmount : lines.joined(separator: "\n")
        }
        
        // Для доходов и расходов: если есть конвертированная сумма и она отличается от основной, показываем обе
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
            return .red
        case .internalTransfer:
            return .blue // Синий цвет для переводов для консистентности с иконкой
        case .depositTopUp, .depositInterestAccrual:
            return .green
        case .depositWithdrawal:
            return .red
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
            // Вычисляем сумму для источника
            let sourceCurrency = source.currency
            let sourceAmount: Double = {
                if transaction.currency == sourceCurrency {
                    return transaction.amount
                } else if let convertedAmount = transaction.convertedAmount {
                    return convertedAmount
                } else if let converted = CurrencyConverter.convertSync(
                    amount: transaction.amount,
                    from: transaction.currency,
                    to: sourceCurrency
                ) {
                    return converted
                } else {
                    return transaction.amount
                }
            }()
            
            // Если есть счет получателя - показываем обе суммы
            if let target = targetAccount {
                let targetCurrency = target.currency
                
                // Вычисляем сумму для получателя
                let targetAmount: Double = {
                    if transaction.currency == targetCurrency {
                        return transaction.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: transaction.amount,
                        from: transaction.currency,
                        to: targetCurrency
                    ) {
                        return converted
                    } else {
                        return transaction.amount
                    }
                }()
                
                // Всегда показываем обе суммы (источника с минусом, получателя с плюсом)
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
                // Если счета получателя нет, показываем только сумму источника
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
