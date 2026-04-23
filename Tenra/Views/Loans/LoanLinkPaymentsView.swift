//
//  LoanLinkPaymentsView.swift
//  Tenra
//
//  Thin wrapper around the shared `LinkPaymentsView` component.
//  Binds `LoanTransactionMatcher` and loan linking to the generic UI.
//

import SwiftUI

struct LoanLinkPaymentsView: View {
    let loan: Account
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    let balanceCoordinator: BalanceCoordinator

    @Environment(TransactionStore.self) private var transactionStore

    var body: some View {
        let loanAccount = loan
        let vm = loansViewModel
        let store = transactionStore

        LinkPaymentsView(
            title: String(localized: "loan.linkPayments.title", defaultValue: "Link Payments"),
            displayCurrency: loan.currency,
            findCandidates: { all, mode in
                LoanTransactionMatcher.findCandidates(for: loanAccount, in: all, mode: mode)
            },
            performLink: { selected in
                try await vm.linkTransactions(
                    toLoan: loanAccount.id,
                    transactions: selected,
                    transactionStore: store
                )
            },
            options: .loan,
            transactionStore: transactionStore,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel
        )
    }
}
