//
//  BrandLogoDisplayView.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//  Purpose: Unified display view for all icon sources (SF Symbols, BankLogo, logo.dev)
//

import SwiftUI

/// Reusable view for displaying brand logos/icons from various sources
/// Eliminates duplication across SubscriptionCard, SubscriptionDetailView, AccountEditView, etc.
struct BrandLogoDisplayView: View {

    // MARK: - Properties

    let iconSource: IconSource?
    let size: CGFloat

    // MARK: - Body

    var body: some View {
        switch iconSource {
        case .sfSymbol(let name):
            sfSymbolView(name)

        case .bankLogo(let logo):
            bankLogoView(logo)

        case .brandService(let name):
            brandServiceView(name)

        case .none:
            placeholderView()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sfSymbolView(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(AppColors.accent)
    }

    @ViewBuilder
    private func bankLogoView(_ logo: BankLogo) -> some View {
        logo.image(size: size)
    }

    @ViewBuilder
    private func brandServiceView(_ name: String) -> some View {
        // Use existing BrandLogoView for logo.dev API
        BrandLogoView(brandName: name, size: size)
    }

    @ViewBuilder
    private func placeholderView() -> some View {
        Image(systemName: "photo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(AppColors.textSecondary)
    }
}

// MARK: - Preview

#Preview("SF Symbol") {
    BrandLogoDisplayView(
        iconSource: .sfSymbol("star.fill"),
        size: AppIconSize.xl
    )
    .padding()
}

#Preview("Bank Logo") {
    BrandLogoDisplayView(
        iconSource: .bankLogo(.kaspi),
        size: AppIconSize.xl
    )
    .padding()
}

#Preview("Brand Service") {
    BrandLogoDisplayView(
        iconSource: .brandService("netflix"),
        size: AppIconSize.xl
    )
    .padding()
}

#Preview("None") {
    BrandLogoDisplayView(
        iconSource: nil,
        size: AppIconSize.xl
    )
    .padding()
}
