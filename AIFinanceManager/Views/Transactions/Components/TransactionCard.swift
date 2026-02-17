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
    let accountsViewModel: AccountsViewModel?   // Phase 16: needed for EditTransactionCoordinator
    let balanceCoordinator: BalanceCoordinator?  // Optional - can't use @ObservedObject with optionals

    @State private var showingStopRecurringConfirmation = false
    @State private var showingEditModal = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""

    // TransactionStore for delete and edit operations
    @Environment(TransactionStore.self) private var transactionStore

    // ✅ CATEGORY REFACTORING: Use cached style data instead of recreating helper
    private var styleData: CategoryStyleData {
        CategoryStyleHelper.cached(category: transaction.category, type: transaction.type, customCategories: customCategories)
    }

    /// Icon source from the subscription series linked to this transaction (nil for generic recurring)
    private var subscriptionIconSource: IconSource? {
        guard let seriesId = transaction.recurringSeriesId else { return nil }
        let series = transactionStore.recurringSeries.first(where: { $0.id == seriesId })
        guard series?.kind == .subscription else { return nil }
        return series?.iconSource
    }

    init(
        transaction: Transaction,
        currency: String,
        customCategories: [CustomCategory],
        accounts: [Account],
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil
    ) {
        self.transaction = transaction
        self.currency = currency
        self.customCategories = customCategories
        self.accounts = accounts
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
    }
    
    // MARK: - Display Helpers (Phase 16: delegated to TransactionDisplayHelper)

    private var isFutureDate: Bool {
        TransactionDisplayHelper.isFutureDate(transaction.date)
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Transaction icon
            TransactionIconView(
                transaction: transaction,
                styleData: styleData,
                subscriptionIconSource: subscriptionIconSource
            )
            
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
                    FormattedAmountView(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        prefix: amountPrefix,
                        color: amountColor
                    )

                    // Если есть вторая валюта (мультивалютные транзакции)
                    if let targetCurrency = transaction.targetCurrency,
                       let targetAmount = transaction.targetAmount,
                       targetCurrency != transaction.currency {
                        HStack(spacing: 0) {
                            Text("(")
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(amountColor.opacity(0.7))
                            FormattedAmountView(
                                amount: targetAmount,
                                currency: targetCurrency,
                                prefix: "",
                                color: amountColor.opacity(0.7)
                            )
                            Text(")")
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(amountColor.opacity(0.7))
                        }
                    }
                }
            }
        }
        .opacity(isFutureDate ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "accessibility.swipeForOptions"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Удаление
            Button(role: .destructive) {
                HapticManager.warning()

                // NEW: Use TransactionStore for delete
                Task {
                    do {
                        try await transactionStore.delete(transaction)
                        HapticManager.success()
                    } catch {
                        // Handle error
                        await MainActor.run {
                            deleteErrorMessage = error.localizedDescription
                            showingDeleteError = true
                            HapticManager.error()
                        }
                    }
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
        .alert("Error", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
        .onTapGesture {
            HapticManager.selection()
            showingEditModal = true
        }
        .sheet(isPresented: $showingEditModal) {
            if let viewModel = viewModel,
               let categoriesViewModel = categoriesViewModel,
               let accountsViewModel = accountsViewModel,
               let balanceCoordinator = balanceCoordinator {
                EditTransactionView(
                    transaction: transaction,
                    transactionsViewModel: viewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    transactionStore: transactionStore,
                    accounts: accounts,
                    customCategories: customCategories,
                    balanceCoordinator: balanceCoordinator
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
        TransactionDisplayHelper.accessibilityText(for: transaction, accounts: accounts)
    }

    private var amountColor: Color {
        TransactionDisplayHelper.amountColor(for: transaction.type)
    }

    private var amountPrefix: String {
        TransactionDisplayHelper.amountPrefix(for: transaction.type)
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
                    FormattedAmountView(
                        amount: sourceAmount,
                        currency: sourceCurrency,
                        prefix: "-",
                        color: .primary
                    )

                    FormattedAmountView(
                        amount: targetAmount,
                        currency: targetCurrency,
                        prefix: "+",
                        color: .green
                    )
                }
            } else {
                FormattedAmountView(
                    amount: sourceAmount,
                    currency: sourceCurrency,
                    prefix: "-",
                    color: .primary
                )
            }
        } else {
            // Если счета источника нет, показываем основную сумму
            FormattedAmountView(
                amount: transaction.amount,
                currency: transaction.currency,
                prefix: "",
                color: amountColor
            )
        }
    }
}

#Preview("Expense") {
    let coordinator = AppCoordinator()
    let sampleTransaction = Transaction(
        id: "preview-expense",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Coffee & Snacks",
        amount: 2500,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? ""
    )

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            customCategories: coordinator.categoriesViewModel.customCategories,
            accounts: coordinator.accountsViewModel.accounts,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Income") {
    let coordinator = AppCoordinator()
    let sampleTransaction = Transaction(
        id: "preview-income",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Salary",
        amount: 450000,
        currency: "KZT",
        type: .income,
        category: "Salary",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? ""
    )

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            customCategories: coordinator.categoriesViewModel.customCategories,
            accounts: coordinator.accountsViewModel.accounts,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Transfer") {
    let coordinator = AppCoordinator()
    let accounts = coordinator.accountsViewModel.accounts
    let sourceId = accounts.first?.id ?? "src"
    let targetId = accounts.dropFirst().first?.id ?? "tgt"

    let sampleTransaction = Transaction(
        id: "preview-transfer",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Between accounts",
        amount: 50000,
        currency: "KZT",
        type: .internalTransfer,
        category: "Transfer",
        accountId: sourceId,
        targetAccountId: targetId
    )

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            customCategories: coordinator.categoriesViewModel.customCategories,
            accounts: accounts,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}

#Preview("Recurring") {
    let coordinator = AppCoordinator()
    let sampleTransaction = Transaction(
        id: "preview-recurring",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Netflix",
        amount: 4990,
        currency: "KZT",
        type: .expense,
        category: "Subscriptions",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? "",
        recurringSeriesId: "series-1"
    )

    List {
        TransactionCard(
            transaction: sampleTransaction,
            currency: "KZT",
            customCategories: coordinator.categoriesViewModel.customCategories,
            accounts: coordinator.accountsViewModel.accounts,
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator
        )
    }
    .listStyle(PlainListStyle())
    .environment(coordinator.transactionStore)
}
