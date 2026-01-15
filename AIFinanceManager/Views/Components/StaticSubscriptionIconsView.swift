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
    
    var body: some View {
        ZStack {
            ForEach(Array(subscriptions.prefix(maxIcons).enumerated()), id: \.element.id) { index, subscription in
                SubscriptionIconView(subscription: subscription, index: index, size: iconSize)
                    .position(iconPosition(for: index, total: min(subscriptions.count, maxIcons)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    private func iconPosition(for index: Int, total: Int) -> CGPoint {
        // Простое размещение в сетке
        let columns = 3
        let _ = (total + columns - 1) / columns
        
        let col = index % columns
        let row = index / columns
        
        let spacing: CGFloat = 8
        let startX: CGFloat = iconSize / 2 + spacing
        let startY: CGFloat = iconSize / 2 + spacing
        
        let x = startX + CGFloat(col) * (iconSize + spacing)
        let y = startY + CGFloat(row) * (iconSize + spacing)
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Subscription Icon View

private struct SubscriptionIconView: View {
    let subscription: RecurringSeries
    let index: Int
    let size: CGFloat
    
    var body: some View {
        Group {
            if let brandLogo = subscription.brandLogo {
                brandLogo.image(size: size)
            } else if let brandId = subscription.brandId, !brandId.isEmpty {
                if brandId.hasPrefix("sf:") {
                    let iconName = String(brandId.dropFirst(3))
                    Image(systemName: iconName)
                        .font(.system(size: size * 0.5))
                        .foregroundColor(.primary)
                        .frame(width: size, height: size)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                } else if brandId.hasPrefix("icon:") {
                    let iconName = String(brandId.dropFirst(5))
                    Image(systemName: iconName)
                        .font(.system(size: size * 0.5))
                        .foregroundColor(.primary)
                        .frame(width: size, height: size)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                } else {
                    // Используем BrandLogoView для логотипов из logo.dev
                    BrandLogoView(brandName: brandId, size: size)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                }
            } else {
                Image(systemName: "creditcard")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.primary)
                    .frame(width: size, height: size)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
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
