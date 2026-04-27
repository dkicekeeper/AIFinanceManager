//
//  SubscriptionsCardView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsCardView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    // Fix #7: Double instead of Decimal — avoids NSDecimalNumber round-trip at the use site.
    @State private var totalAmount: Double = 0
    @State private var isLoadingTotal: Bool = false
    /// Subscription amounts converted to base currency for PackedCircleIconsView sizing.
    @State private var convertedAmounts: [String: Double] = [:]

    private var subscriptions: [RecurringSeries] {
        transactionStore.activeSubscriptions
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Combined key driving .task(id:) — restarts automatically when count or currency changes.
    private var refreshID: String {
        "\(subscriptions.count)-\(baseCurrency)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "subscriptions.title"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)

                if subscriptions.isEmpty {
                    EmptyStateView(title: String(localized: "emptyState.noActiveSubscriptions"), style: .compact)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ZStack {
                            if isLoadingTotal {
                                Text("0000.00")
                                    .font(AppTypography.h2)
                                    .fontWeight(.bold)
                                    .redacted(reason: .placeholder)
                                    .transition(.opacity)
                            } else {
                                FormattedAmountText(
                                    amount: totalAmount,
                                    currency: baseCurrency,
                                    fontSize: AppTypography.h2,
                                    fontWeight: .bold,
                                    color: AppColors.textPrimary
                                )
                                .transition(.opacity)
                            }
                        }
                        .animation(AppAnimation.gentleSpring, value: isLoadingTotal)

                        Text(String(format: String(localized: "subscriptions.activeCount"), subscriptions.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !subscriptions.isEmpty {
                PackedCircleIconsView(
                    items: subscriptions.map { sub in
                        PackedCircleItem(
                            id: sub.id,
                            iconSource: sub.iconSource,
                            amount: convertedAmounts[sub.id] ?? (sub.amount as NSDecimalNumber).doubleValue
                        )
                    }
                )
            }
        }
        .animation(AppAnimation.gentleSpring, value: subscriptions.isEmpty)
        .padding(AppSpacing.lg)
        .cardStyle()
        // Fix #3: replaced two separate `onChange + unstructured Task {}` blocks with a single
        // `.task(id: refreshID)`. SwiftUI automatically cancels and restarts this task whenever
        // `refreshID` changes (subscriptions count or base currency), and cancels it on view
        // removal — no task leaks on sheet dismiss.
        .task(id: refreshID) {
            await refreshTotal()
        }
    }

    /// Calculate total subscription amount in base currency.
    private func refreshTotal() async {
        // Show the redacted placeholder only on the very first load — refreshing
        // an already-displayed value over the placeholder is jarring and reads as a
        // flicker on every recurring-series mutation.
        let isFirstLoad = totalAmount == 0
        if isFirstLoad { isLoadingTotal = true }

        let baseCur = baseCurrency
        // Snapshot subscription scalars on MainActor so the TaskGroup body works
        // with Sendable value types only — avoids capturing RecurringSeries refs.
        let subTuples: [(id: String, currency: String, raw: Double)] = subscriptions.map {
            (id: $0.id, currency: $0.currency, raw: ($0.amount as NSDecimalNumber).doubleValue)
        }

        // Compute total and per-subscription conversions in parallel. The total query
        // hits CurrencyConverter once; the per-sub loop did N sequential awaits before.
        async let totalResult = transactionStore.calculateSubscriptionsTotalInCurrency(baseCur)
        async let amountsByID: [String: Double] = withTaskGroup(of: (String, Double).self) { group in
            for sub in subTuples {
                group.addTask {
                    if sub.currency == baseCur { return (sub.id, sub.raw) }
                    let converted = await CurrencyConverter.convert(
                        amount: sub.raw, from: sub.currency, to: baseCur
                    )
                    return (sub.id, converted ?? sub.raw)
                }
            }
            var dict: [String: Double] = [:]
            dict.reserveCapacity(subTuples.count)
            for await (id, amount) in group {
                dict[id] = amount
            }
            return dict
        }

        let result = await totalResult
        let amounts = await amountsByID

        totalAmount = (result.total as NSDecimalNumber).doubleValue
        convertedAmounts = amounts
        isLoadingTotal = false
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubscriptionsCardView(
        transactionStore: coordinator.transactionStore,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .screenPadding()
}
