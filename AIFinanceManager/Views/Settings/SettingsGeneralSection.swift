//
//  SettingsGeneralSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//  Updated: HomeBackgroundPicker replaces WallpaperPickerRow
//

import SwiftUI
import PhotosUI

/// Props-based General section for Settings.
/// Groups currency picker + Apple-style home background picker.
struct SettingsGeneralSection: View {

    // MARK: - Props

    let selectedCurrency: String
    let availableCurrencies: [String]
    let currentBackgroundMode: HomeBackgroundMode
    let wallpaperImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    let onCurrencyChange: (String) -> Void
    let onBackgroundModeChange: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.general"))) {
            // Base Currency Picker
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: AppIconSize.md))
                    .foregroundStyle(AppColors.accent)

                Text(String(localized: "settings.baseCurrency"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Menu {
                    ForEach(availableCurrencies, id: \.self) { currency in
                        Button {
                            onCurrencyChange(currency)
                        } label: {
                            HStack {
                                Text(Formatting.currencySymbol(for: currency))
                                if selectedCurrency == currency {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(Formatting.currencySymbol(for: selectedCurrency))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }

        // Background picker in its own section for visual breathing room
        Section(header: SettingsSectionHeaderView(
            title: String(localized: "settings.background", defaultValue: "Background")
        )) {
            HomeBackgroundPicker(
                currentMode: currentBackgroundMode,
                wallpaperImage: wallpaperImage,
                selectedPhoto: $selectedPhoto,
                onModeSelect: onBackgroundModeChange,
                onPhotoChange: onPhotoChange,
                onWallpaperRemove: onWallpaperRemove
            )
            .listRowInsets(EdgeInsets(top: AppSpacing.sm,
                                      leading: 0,
                                      bottom: AppSpacing.sm,
                                      trailing: 0))
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedPhoto: PhotosPickerItem? = nil
        @State private var mode: HomeBackgroundMode = .none

        var body: some View {
            List {
                SettingsGeneralSection(
                    selectedCurrency: "KZT",
                    availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
                    currentBackgroundMode: mode,
                    wallpaperImage: nil,
                    selectedPhoto: $selectedPhoto,
                    onCurrencyChange: { _ in },
                    onBackgroundModeChange: { mode = $0 },
                    onPhotoChange: { _ in },
                    onWallpaperRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
