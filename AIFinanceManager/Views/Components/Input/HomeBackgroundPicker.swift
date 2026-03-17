//
//  HomeBackgroundPicker.swift
//  AIFinanceManager
//
//  Apple Wallpaper-style picker for the home screen background mode.
//  Three mode cards in a horizontal scroll — None / Gradient / Photo —
//  followed by a contextual photo picker row when Wallpaper mode is active.
//

import SwiftUI
import PhotosUI

// MARK: - HomeBackgroundPicker

/// Horizontal card picker that lets users choose between three background modes.
///
/// Layout mirrors iOS Settings › Wallpaper:
/// - Scrollable row of thumbnail cards, one per mode
/// - Selected card gets an accent border + ✓ badge
/// - When `.wallpaper` is selected a PhotosPicker row appears below
struct HomeBackgroundPicker: View {

    // MARK: - Props

    let currentMode: HomeBackgroundMode
    /// Thumbnail of the saved wallpaper (nil when none saved yet).
    let wallpaperImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    let onModeSelect: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void

    // MARK: - Layout constants

    private let cardWidth: CGFloat  = 100
    private let cardHeight: CGFloat = 168   // ~9:16 phone aspect ratio

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Mode cards row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(HomeBackgroundMode.allCases, id: \.self) { mode in
                        modeCard(mode)
                            .onTapGesture { onModeSelect(mode) }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            }

            // Photo picker row — visible only when wallpaper mode is active
            if currentMode == .wallpaper {
                wallpaperActionRow
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(AppAnimation.gentleSpring, value: currentMode)
    }

    // MARK: - Mode Card

    @ViewBuilder
    private func modeCard(_ mode: HomeBackgroundMode) -> some View {
        let isSelected = currentMode == mode

        ZStack(alignment: .bottom) {
            // Card artwork
            modeArtwork(mode)
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(.rect(cornerRadius: AppRadius.xl))

            // Mode label
            Text(mode.localizedTitle)
                .font(AppTypography.caption)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                .padding(.bottom, AppSpacing.sm)

            // Selection checkmark badge
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: AppIconSize.md, weight: .semibold))
                            .foregroundStyle(.white)
                            .background(
                                Circle().fill(AppColors.accent).padding(-2)
                            )
                            .padding(AppSpacing.sm)
                    }
                    Spacer()
                }
            }
        }
        // Selected border
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .stroke(
                    isSelected ? AppColors.accent : Color.clear,
                    lineWidth: 3
                )
        )
        .animation(AppAnimation.contentSpring, value: isSelected)
        .accessibilityLabel(mode.localizedTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Card Artwork

    @ViewBuilder
    private func modeArtwork(_ mode: HomeBackgroundMode) -> some View {
        switch mode {
        case .none:
            // System background — adapts to light/dark automatically
            Rectangle()
                .fill(Color(.systemGroupedBackground))
                .overlay(
                    Image(systemName: "iphone")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Color(.tertiaryLabel))
                )

        case .gradient:
            // Static preview using palette colours — looks like actual gradient
            GeometryReader { geo in
                ZStack {
                    // Dark base to make colours pop
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.05, blue: 0.12),
                                     Color(red: 0.08, green: 0.05, blue: 0.18)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // Orb 1 — blue/indigo (top-left)
                    Ellipse()
                        .fill(Color(red: 0.231, green: 0.510, blue: 0.965).opacity(0.65))
                        .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.5)
                        .offset(x: -geo.size.width * 0.15, y: -geo.size.height * 0.20)
                        .blur(radius: 22)
                    // Orb 2 — purple (top-right)
                    Ellipse()
                        .fill(Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.55))
                        .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.45)
                        .offset(x: geo.size.width * 0.20, y: -geo.size.height * 0.05)
                        .blur(radius: 20)
                    // Orb 3 — pink (bottom)
                    Ellipse()
                        .fill(Color(red: 0.925, green: 0.255, blue: 0.600).opacity(0.50))
                        .frame(width: geo.size.width * 0.85, height: geo.size.height * 0.4)
                        .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.25)
                        .blur(radius: 22)
                }
            }

        case .wallpaper:
            if let image = wallpaperImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder: prompt user to pick a photo
                Rectangle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        VStack(spacing: AppSpacing.xs) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(AppColors.accent)
                            Text(String(localized: "settings.background.addPhoto",
                                        defaultValue: "Add Photo"))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.accent)
                        }
                    )
            }
        }
    }

    // MARK: - Wallpaper Action Row

    private var wallpaperActionRow: some View {
        HStack(spacing: AppSpacing.md) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(
                    wallpaperImage != nil
                        ? String(localized: "button.change", defaultValue: "Change")
                        : String(localized: "button.select", defaultValue: "Select"),
                    systemImage: wallpaperImage != nil ? "photo.badge.arrow.down" : "photo"
                )
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.accent)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await onPhotoChange(newItem) }
            }

            if wallpaperImage != nil {
                Divider().frame(height: 16)

                Button(role: .destructive) {
                    Task { await onWallpaperRemove() }
                } label: {
                    Label(String(localized: "button.remove", defaultValue: "Remove"),
                          systemImage: "trash")
                        .font(AppTypography.bodySmall)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - HomeBackgroundMode + display helpers

private extension HomeBackgroundMode {
    var localizedTitle: String {
        switch self {
        case .none:      return String(localized: "settings.background.none",
                                       defaultValue: "None")
        case .gradient:  return String(localized: "settings.background.gradient",
                                       defaultValue: "Gradient")
        case .wallpaper: return String(localized: "settings.background.photo",
                                       defaultValue: "Photo")
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var mode: HomeBackgroundMode = .none
        @State private var photo: PhotosPickerItem?

        var body: some View {
            List {
                Section("Background") {
                    HomeBackgroundPicker(
                        currentMode: mode,
                        wallpaperImage: nil,
                        selectedPhoto: $photo,
                        onModeSelect: { mode = $0 },
                        onPhotoChange: { _ in },
                        onWallpaperRemove: {}
                    )
                    .listRowInsets(EdgeInsets())
                }
            }
        }
    }
    return PreviewWrapper()
}
