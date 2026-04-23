//
//  DepositLinkInterestView.swift
//  Tenra
//
//  Thin wrapper around the shared `LinkPaymentsView` component.
//  Binds `DepositInterestMatcher` and the deposit-interest linker to the generic UI.
//

import SwiftUI

struct DepositLinkInterestView: View {
    let deposit: Account
    let depositsViewModel: DepositsViewModel
    let transactionStore: TransactionStore
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        let account = deposit
        let vm = depositsViewModel
        let store = transactionStore

        LinkPaymentsView(
            title: String(localized: "deposit.linkInterest.title", defaultValue: "Link Interest Payments"),
            displayCurrency: deposit.currency,
            findCandidates: { all, mode in
                DepositInterestMatcher.findCandidates(for: account, in: all, mode: mode)
            },
            performLink: { selected in
                try await vm.linkTransactionsAsInterest(
                    depositId: account.id,
                    transactions: selected,
                    transactionStore: store
                )
            },
            options: .deposit,
            transactionStore: transactionStore,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel
        )
    }
}
