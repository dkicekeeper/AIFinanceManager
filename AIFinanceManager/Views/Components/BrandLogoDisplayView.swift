//
//  BrandLogoDisplayView.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//  Purpose: Reusable component for displaying brand logos
//

import SwiftUI

/// Reusable view for displaying brand logos with various sources
/// Eliminates duplication across SubscriptionCard, SubscriptionDetailView, SubscriptionEditView, etc.
struct BrandLogoDisplayView: View {

    // MARK: - Properties

    let brandLogo: BankLogo?
    let brandId: String?
    let brandName: String?
    let size: CGFloat

    // MARK: - Computed Properties

    private var logoSource: BrandLogoDisplayHelper.LogoSource {
        BrandLogoDisplayHelper.resolveSource(
            brandLogo: brandLogo,
            brandId: brandId,
            brandName: brandName
        )
    }

    // MARK: - Body

    var body: some View {
        switch logoSource {
        case .systemImage(let iconName):
            systemImageView(iconName)

        case .customIcon(let iconName):
            customIconView(iconName)

        case .brandService(let name):
            brandServiceView(name)

        case .bankLogo(let logo):
            bankLogoView(logo)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func systemImageView(_ iconName: String) -> some View {
        Image(systemName: iconName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(.accentColor)
    }

    @ViewBuilder
    private func customIconView(_ iconName: String) -> some View {
        Image(iconName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private func brandServiceView(_ name: String) -> some View {
        // Use existing BrandLogoView for logo.dev API
        BrandLogoView(brandName: name, size: size)
    }

    @ViewBuilder
    private func bankLogoView(_ logo: BankLogo) -> some View {
        logo.image(size: size)
    }
}

// MARK: - Preview

#Preview("System Image") {
    BrandLogoDisplayView(
        brandLogo: nil,
        brandId: "sf:star.fill",
        brandName: nil,
        size: 40
    )
}

#Preview("Custom Icon") {
    BrandLogoDisplayView(
        brandLogo: nil,
        brandId: "icon:netflix",
        brandName: nil,
        size: 40
    )
}

#Preview("Brand Service") {
    BrandLogoDisplayView(
        brandLogo: nil,
        brandId: nil,
        brandName: "netflix",
        size: 40
    )
}

#Preview("Bank Logo") {
    BrandLogoDisplayView(
        brandLogo: .sber,
        brandId: nil,
        brandName: nil,
        size: 40
    )
}
