//
//  DepositDetailView.swift
//  AIFinanceManager
//
//  Detail view for deposit accounts
//

import SwiftUI

struct DepositDetailView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let accountId: String
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var showingEditView = false
    @State private var showingTransferTo = false // Пополнение депозита
    @State private var showingTransferFrom = false // Перевод с депозита на счет
    @State private var showingRateChange = false
    @State private var showingDeleteConfirmation = false
    @State private var showingHistory = false
    @Environment(\.dismiss) var dismiss
    
    private var account: Account? {
        viewModel.accounts.first(where: { $0.id == accountId })
    }
    
    private var depositInfo: DepositInfo? {
        account?.depositInfo
    }
    
    var body: some View {
        Group {
            if let account = account {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Info card
                        if let depositInfo = depositInfo {
                            depositInfoCard(depositInfo: depositInfo, account: account)
                                .screenPadding()
                            
                            // Actions
                            actionsSection
                                .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .navigationTitle(account.name)
            } else {
                Text("Депозит не найден")
                    .navigationTitle("Депозит")
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditView = true
                    } label: {
                        Label("Редактировать", systemImage: "pencil")
                    }
                    
                    Button {
                        showingRateChange = true
                    } label: {
                        Label("Изменить ставку", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Удалить депозит", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            if let account = account {
                NavigationView {
                    HistoryView(viewModel: viewModel, initialAccountId: account.id)
                        .environmentObject(timeFilterManager)
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            if let account = account {
                DepositEditView(
                    viewModel: viewModel,
                    account: account,
                    onSave: { updatedAccount in
                        viewModel.updateDeposit(updatedAccount)
                        showingEditView = false
                    },
                    onCancel: {
                        showingEditView = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingTransferTo) {
            if let account = account {
                AccountActionView(viewModel: viewModel, account: account, transferDirection: .toDeposit)
                    .environmentObject(timeFilterManager)
            }
        }
        .sheet(isPresented: $showingTransferFrom) {
            if let account = account {
                AccountActionView(viewModel: viewModel, account: account, transferDirection: .fromDeposit)
                    .environmentObject(timeFilterManager)
            }
        }
        .sheet(isPresented: $showingRateChange) {
            if let account = account {
                DepositRateChangeView(
                    viewModel: viewModel,
                    account: account,
                    onComplete: {
                        showingRateChange = false
                    }
                )
            }
        }
        .alert("Удалить депозит?", isPresented: $showingDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                if let account = account {
                    viewModel.deleteDeposit(account)
                }
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все данные депозита и связанные транзакции будут удалены.")
        }
        .onAppear {
            // Пересчитываем проценты при открытии
            viewModel.reconcileAllDeposits()
        }
    }
    
    private func depositInfoCard(depositInfo: DepositInfo, account: Account) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header
                HStack {
                    account.bankLogo.image(size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name)
                            .font(AppTypography.h3)
                        Text(depositInfo.bankName)
                            .font(AppTypography.bodySmall)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                // Balance
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Баланс")
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(AppTypography.h2)
                }
                
                // Interest info
                let interestToToday = DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Проценты на сегодня")
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                    Text(Formatting.formatCurrency(NSDecimalNumber(decimal: interestToToday).doubleValue, currency: account.currency))
                        .font(AppTypography.h4)
                        .foregroundColor(.blue)
                }
                
                Divider()
                
                // Details
                InfoRow(label: "Ставка", value: "\(formatRate(depositInfo.interestRateAnnual))% годовых")
                InfoRow(label: "Капитализация", value: depositInfo.capitalizationEnabled ? "Включена" : "Выключена")
                InfoRow(label: "День начисления", value: "\(depositInfo.interestPostingDay)")
                
                if let nextPosting = DepositInterestService.nextPostingDate(depositInfo: depositInfo) {
                    InfoRow(label: "Следующее начисление", value: formatDate(nextPosting))
                }
            }
            .padding(AppSpacing.md)
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                showingTransferTo = true
            } label: {
                Label("Пополнить", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()
            
            Button {
                showingTransferFrom = true
            } label: {
                Label("Перевести на счет", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func formatRate(_ rate: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: rate).doubleValue)
    }
    
    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }
}

// MARK: - Deposit Transfer View

enum DepositTransferDirection {
    case toDeposit  // Перевод на депозит (пополнение)
    case fromDeposit // Перевод с депозита (снятие)
}

struct DepositTransferView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let depositAccount: Account
    let transferDirection: DepositTransferDirection
    let onComplete: () -> Void
    
    @State private var selectedSourceAccountId: String? = nil
    @State private var amountText: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isAmountFocused: Bool
    
    private var availableAccounts: [Account] {
        viewModel.accounts.filter { $0.id != depositAccount.id }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Счет \(transferDirection == .toDeposit ? "источника" : "получателя")")) {
                    if availableAccounts.isEmpty {
                        Text("Нет других счетов для перевода")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.md) {
                                ForEach(availableAccounts) { sourceAccount in
                                    AccountRadioButton(
                                        account: sourceAccount,
                                        isSelected: selectedSourceAccountId == sourceAccount.id,
                                        onTap: {
                                            selectedSourceAccountId = sourceAccount.id
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section(header: Text("Сумма")) {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                }
                
                Section(header: Text("Описание")) {
                    TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Дата")) {
                    DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                }
            }
            .navigationTitle(transferDirection == .toDeposit ? "Пополнить депозит" : "Перевести с депозита")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        onComplete()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveTransfer()
                    }
                    .disabled(amountText.isEmpty || selectedSourceAccountId == nil)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isAmountFocused = true
                }
                descriptionText = transferDirection == .toDeposit ? "Пополнение депозита" : "Перевод с депозита"
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveTransfer() {
        guard let sourceAccountId = selectedSourceAccountId,
              let amount = AmountFormatter.parse(amountText) else {
            return
        }
        
        let dateString = DateFormatters.dateFormatter.string(from: selectedDate)
        let description = descriptionText.isEmpty 
            ? (transferDirection == .toDeposit ? "Пополнение депозита" : "Перевод с депозита")
            : descriptionText
        
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
        
        if transferDirection == .toDeposit {
            // Перевод на депозит (с выбранного счета на депозит)
            viewModel.transfer(
                from: sourceAccountId,
                to: depositAccount.id,
                amount: amountDouble,
                date: dateString,
                description: description
            )
        } else {
            // Перевод с депозита (с депозита на выбранный счет)
            viewModel.transfer(
                from: depositAccount.id,
                to: sourceAccountId,
                amount: amountDouble,
                date: dateString,
                description: description
            )
        }
        
        onComplete()
    }
}

struct DepositRateChangeView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let account: Account
    let onComplete: () -> Void
    
    @State private var rateText: String = ""
    @State private var effectiveFromDate: Date = Date()
    @State private var noteText: String = ""
    @FocusState private var isRateFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Новая процентная ставка")) {
                    HStack {
                        TextField("0.0", text: $rateText)
                            .keyboardType(.decimalPad)
                            .focused($isRateFocused)
                        Text("% годовых")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Дата вступления в силу")) {
                    DatePicker("Дата", selection: $effectiveFromDate, displayedComponents: .date)
                }
                
                Section(header: Text("Примечание (необязательно)")) {
                    TextField("Примечание", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Изменить ставку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        onComplete()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveRateChange()
                    }
                    .disabled(rateText.isEmpty)
                }
            }
            .onAppear {
                if let depositInfo = account.depositInfo {
                    rateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isRateFocused = true
                }
            }
        }
    }
    
    private func saveRateChange() {
        guard let rate = AmountFormatter.parse(rateText) else { return }
        
        let dateString = DateFormatters.dateFormatter.string(from: effectiveFromDate)
        let note = noteText.isEmpty ? nil : noteText
        
        viewModel.addDepositRateChange(
            accountId: account.id,
            effectiveFrom: dateString,
            annualRate: rate,
            note: note
        )
        
        onComplete()
    }
}


struct DepositTransactionRow: View {
    let transaction: Transaction
    let currency: String
    let depositAccountId: String
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: iconForTransactionType(transaction.type))
                .foregroundColor(colorForTransactionType(transaction.type))
                .font(.caption)
                .frame(width: 20)
            
            // Date and description
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(AppTypography.body)
                Text(formatDate(transaction.date))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount
            Text(formatAmount(transaction))
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(colorForTransactionType(transaction.type))
        }
        .padding(AppSpacing.sm)
        .background(Color(.systemGray6))
        .cornerRadius(AppRadius.sm)
    }
    
    private func iconForTransactionType(_ type: TransactionType) -> String {
        switch type {
        case .internalTransfer:
            return "arrow.left.arrow.right.circle.fill"
        case .depositInterestAccrual:
            return "percent"
        default:
            return "circle"
        }
    }
    
    private func colorForTransactionType(_ type: TransactionType) -> Color {
        switch type {
        case .internalTransfer:
            return .blue
        case .depositInterestAccrual:
            return .green
        default:
            return .primary
        }
    }
    
    private func formatAmount(_ transaction: Transaction) -> String {
        // Для переводов определяем направление на основе depositAccountId
        if transaction.type == .depositInterestAccrual {
            return "+\(Formatting.formatCurrency(transaction.amount, currency: currency))"
        } else if transaction.type == .internalTransfer {
            // Если депозит - получатель, это пополнение (+)
            let isIncoming = transaction.targetAccountId == depositAccountId
            let sign = isIncoming ? "+" : "-"
            return "\(sign)\(Formatting.formatCurrency(transaction.amount, currency: currency))"
        }
        return Formatting.formatCurrency(transaction.amount, currency: currency)
    }
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else {
            return dateString
        }
        return DateFormatters.displayDateFormatter.string(from: date)
    }
}
