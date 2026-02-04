//
//  SettingsGeneralSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI
import PhotosUI

/// Props-based General section for Settings
/// Single Responsibility: Group general settings (currency, wallpaper)
struct SettingsGeneralSection: View {
    // MARK: - Props

    let selectedCurrency: String
    let availableCurrencies: [String]
    let hasWallpaper: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    let onCurrencyChange: (String) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.general"))) {
            BaseCurrencyPickerRow(
                selectedCurrency: selectedCurrency,
                availableCurrencies: availableCurrencies,
                onChange: onCurrencyChange
            )

            WallpaperPickerRow(
                hasWallpaper: hasWallpaper,
                selectedPhoto: $selectedPhoto,
                onPhotoChange: onPhotoChange,
                onRemove: onWallpaperRemove
            )
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedPhoto: PhotosPickerItem? = nil

        var body: some View {
            List {
                SettingsGeneralSection(
                    selectedCurrency: "KZT",
                    availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
                    hasWallpaper: true,
                    selectedPhoto: $selectedPhoto,
                    onCurrencyChange: { _ in },
                    onPhotoChange: { _ in },
                    onWallpaperRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
