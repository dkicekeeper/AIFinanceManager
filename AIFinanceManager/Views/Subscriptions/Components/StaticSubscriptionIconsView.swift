//
//  StaticSubscriptionIconsView.swift
//  AIFinanceManager
//
//  Static display of subscription icons
//

import SwiftUI

struct StaticSubscriptionIconsView: View {
    let subscriptions: [RecurringSeries]
    let maxIcons: Int = 20
    private let iconSize: CGFloat = 32
    private let columns = 3
    private let spacing: CGFloat = 8

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(iconSize), spacing: spacing), count: columns),
            alignment: .center,
            spacing: spacing
        ) {
            ForEach(subscriptions.prefix(maxIcons)) { subscription in
                SubscriptionIconView(subscription: subscription, size: iconSize)
            }
        }
        .padding(spacing)
    }
}

// MARK: - Subscription Icon View

private struct SubscriptionIconView: View {
    let subscription: RecurringSeries
    let size: CGFloat

    var body: some View {
        BrandLogoDisplayView(
            iconSource: subscription.iconSource,
            size: size
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 2)
        )
    }
}

#Preview {
    StaticSubscriptionIconsView(subscriptions: [])
        .padding()
}
