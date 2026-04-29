//
//  AccountActionView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let account: Account
    let namespace: Namespace.ID
    @Environment(\.dismiss) var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var viewModel: AccountActionViewModel
    @State private var showingAccountHistory = false

    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        account: Account,
        namespace: Namespace.ID,
        categoriesViewModel: CategoriesViewModel,
        transferDirection: DepositTransferDirection? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.account = account
        self.namespace = namespace
        self.categoriesViewModel = categoriesViewModel
        _viewModel = State(initialValue: AccountActionViewModel(
            account: account,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel,
            transferDirection: transferDirection
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Color.clear
                    .frame(height: 0)
                    .glassEffectID("account-card-\(account.id)", in: namespace) // glass morph anchor

                // 2. Сумма с выбором валюты
                AmountInputView(
                    amount: $viewModel.amountText,
                    selectedCurrency: $viewModel.selectedCurrency,
                    errorMessage: viewModel.showingError ? viewModel.errorMessage : nil,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                    accountCurrencies: Set(accountsViewModel.accounts.map(\.currency)),
                    appSettings: transactionsViewModel.appSettings
                )

                // 3. Счет
                if viewModel.selectedAction == .income && !account.isDeposit {
                    // Для пополнения счет не нужен
                    EmptyView()
                } else {
                    if let coordinator = accountsViewModel.balanceCoordinator {
                        AccountSelectorView(
                            accounts: viewModel.availableAccounts,
                            selectedAccountId: $viewModel.selectedTargetAccountId,
                            emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                            balanceCoordinator: coordinator
                        )
                    }
                }

                // 4. Категория (только для пополнения)
                if viewModel.selectedAction == .income && !account.isDeposit {
                    CategorySelectorView(
                        categories: viewModel.incomeCategories,
                        type: .income,
                        customCategories: transactionsViewModel.customCategories,
                        selectedCategory: $viewModel.selectedCategory,
                        emptyStateMessage: String(localized: "transactionForm.noCategories")
                    )
                }

                // 5. Описание
                FormTextField(
                    text: $viewModel.descriptionText,
                    placeholder: String(localized: "transactionForm.descriptionPlaceholder"),
                    style: .multiline(min: 2, max: 6)
                )
            }
        }
        .safeAreaBar(edge: .top) {
            if account.isDeposit {
                // Deposits: single entry point, user picks direction here.
                SegmentedPickerView(
                    title: String(localized: "common.type"),
                    selection: Binding(
                        get: { viewModel.transferDirection ?? .toDeposit },
                        set: { viewModel.transferDirection = $0 }
                    ),
                    options: [
                        (label: String(localized: "transactionForm.depositTopUp"), value: DepositTransferDirection.toDeposit),
                        (label: String(localized: "transactionForm.depositWithdrawal"), value: DepositTransferDirection.fromDeposit)
                    ]
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(Color.clear)
            } else {
                SegmentedPickerView(
                    title: String(localized: "common.type"),
                    selection: $viewModel.selectedAction,
                    options: [
                        (label: String(localized: "transactionForm.transfer"), value: AccountActionViewModel.ActionType.transfer),
                        (label: String(localized: "transactionForm.topUp"), value: AccountActionViewModel.ActionType.income)
                    ]
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(Color.clear)
            }
        }
        .navigationTitle(viewModel.navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAccountHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .dateButtonsSafeArea(selectedDate: $viewModel.selectedDate, onSave: { date in
            Task { await viewModel.saveTransaction(date: date, transactionStore: transactionStore) }
        })
        .sheet(isPresented: $showingAccountHistory) {
            NavigationStack {
                HistoryView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    paginationController: appCoordinator.transactionPaginationController,
                    initialAccountId: account.id
                )
                    .environment(timeFilterManager)
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, should in
            if should { dismiss() }
        }
        .alert(String(localized: "common.error"), isPresented: $viewModel.showingError) {
            Button(String(localized: "voice.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

// CategoryRadioButton is now replaced by CategoryChip

// MARK: - Previews

private func makeDepositInfo(
    bank: String = "Tenra Bank",
    principal: Decimal = 100_000,
    rate: Decimal = 12,
    capitalization: Bool = true
) -> DepositInfo {
    DepositInfo(
        bankName: bank,
        principalBalance: principal,
        capitalizationEnabled: capitalization,
        interestRateAnnual: rate,
        interestPostingDay: 15
    )
}

@MainActor
private func makePreviewWrapper(
    account: Account,
    transferDirection: DepositTransferDirection? = nil
) -> some View {
    let coordinator = AppCoordinator()
    return AccountActionPreviewWrapper(
        coordinator: coordinator,
        account: account,
        transferDirection: transferDirection
    )
}

private struct AccountActionPreviewWrapper: View {
    let coordinator: AppCoordinator
    let account: Account
    let transferDirection: DepositTransferDirection?
    @Namespace private var ns

    var body: some View {
        NavigationStack {
            AccountActionView(
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                account: account,
                namespace: ns,
                categoriesViewModel: coordinator.categoriesViewModel,
                transferDirection: transferDirection
            )
        }
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}

#Preview("Regular account (USD)") {
    makePreviewWrapper(
        account: Account(
            name: "Main Card",
            currency: "USD",
            iconSource: .sfSymbol("creditcard.fill"),
            initialBalance: 1_234.56
        )
    )
}

#Preview("Regular account — brand logo") {
    makePreviewWrapper(
        account: Account(
            name: "Revolut",
            currency: "EUR",
            iconSource: .brandService("revolut.com"),
            initialBalance: 5_280
        )
    )
}

#Preview("Regular account — empty balance") {
    makePreviewWrapper(
        account: Account(
            name: "New Wallet",
            currency: "GBP",
            iconSource: .sfSymbol("wallet.bifold.fill"),
            initialBalance: 0
        )
    )
}

#Preview("Deposit — default (top-up)") {
    makePreviewWrapper(
        account: Account(
            name: "12% Term Deposit",
            currency: "USD",
            iconSource: .sfSymbol("banknote.fill"),
            depositInfo: makeDepositInfo(),
            initialBalance: 100_000
        )
    )
}

#Preview("Deposit — withdrawal direction") {
    makePreviewWrapper(
        account: Account(
            name: "12% Term Deposit",
            currency: "USD",
            iconSource: .sfSymbol("banknote.fill"),
            depositInfo: makeDepositInfo(),
            initialBalance: 100_000
        ),
        transferDirection: .fromDeposit
    )
}

#Preview("Deposit — high-yield, no capitalization") {
    makePreviewWrapper(
        account: Account(
            name: "Premium Savings",
            currency: "EUR",
            iconSource: .sfSymbol("star.circle.fill"),
            depositInfo: makeDepositInfo(
                bank: "Premium Bank",
                principal: 500_000,
                rate: 18,
                capitalization: false
            ),
            initialBalance: 500_000
        ),
        transferDirection: .toDeposit
    )
}
