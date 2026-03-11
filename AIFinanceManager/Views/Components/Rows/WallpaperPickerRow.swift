//
//  WallpaperPickerRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI
import PhotosUI

/// Props-based wallpaper picker row for Settings
/// Single Responsibility: Display and handle wallpaper selection/removal
struct WallpaperPickerRow: View {
    // MARK: - Props

    let hasWallpaper: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onRemove: () async -> Void

    // MARK: - Body

    var body: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol("photo", color: AppColors.accent)
        ) {
            Text(String(localized: "settings.wallpaper"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        } trailing: {
            HStack(spacing: AppSpacing.sm) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: AppSpacing.xs) {
                        if hasWallpaper {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: AppIconSize.sm))
                                .foregroundStyle(AppColors.success)
                        }
                        Text(hasWallpaper
                            ? String(localized: "button.change")
                            : String(localized: "button.select")
                        )
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.accent)
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        await onPhotoChange(newItem)
                    }
                }

                if hasWallpaper {
                    Button(action: {
                        Task {
                            await onRemove()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedPhoto: PhotosPickerItem? = nil

        var body: some View {
            List {
                WallpaperPickerRow(
                    hasWallpaper: false,
                    selectedPhoto: $selectedPhoto,
                    onPhotoChange: { _ in },
                    onRemove: {}
                )

                WallpaperPickerRow(
                    hasWallpaper: true,
                    selectedPhoto: $selectedPhoto,
                    onPhotoChange: { _ in },
                    onRemove: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
