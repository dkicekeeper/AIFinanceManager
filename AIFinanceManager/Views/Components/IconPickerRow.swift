//
//  IconPickerRow.swift
//  AIFinanceManager
//
//  Standardized row component for icon/logo selection
//  Opens IconPickerView sheet with consistent styling
//

import SwiftUI

/// Standardized row for opening icon picker
/// Shows current icon preview with chevron, opens IconPickerView on tap
struct IconPickerRow: View {
    @Binding var selectedSource: IconSource?
    let title: String
    let iconSize: CGFloat
    @State private var showingPicker = false

    init(
        selectedSource: Binding<IconSource?>,
        title: String = String(localized: "common.icon"),
        iconSize: CGFloat = AppIconSize.xl
    ) {
        self._selectedSource = selectedSource
        self.title = title
        self.iconSize = iconSize
    }

    var body: some View {
        Button {
            HapticManager.light()
            showingPicker = true
        } label: {
            HStack(spacing: AppSpacing.md) {
                Text(title)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                // Icon preview
                if let source = selectedSource {
                    IconView(
                        source: source,
                        size: iconSize
                    )
                } else {
                    // Placeholder when no icon selected
                    Image(systemName: "photo")
                        .font(.system(size: iconSize * 0.6))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: iconSize, height: iconSize)
                        .background(AppColors.surface)
                        .clipShape(.rect(cornerRadius: iconSize * 0.2))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
        }
        .sheet(isPresented: $showingPicker) {
            IconPickerView(selectedSource: $selectedSource)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Previews

#Preview("With Icon") {
    @Previewable @State var source: IconSource? = .sfSymbol("star.fill")

    return IconPickerRow(selectedSource: $source)
        .background(AppColors.cardBackground)
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .padding()
}

#Preview("Without Icon") {
    @Previewable @State var source: IconSource? = nil

    return IconPickerRow(
        selectedSource: $source,
        title: String(localized: "common.logo")
    )
    .background(AppColors.cardBackground)
    .clipShape(.rect(cornerRadius: AppRadius.md))
    .padding()
}

#Preview("With Bank Logo") {
    @Previewable @State var source: IconSource? = .bankLogo(.kaspi)

    return IconPickerRow(selectedSource: $source)
        .background(AppColors.cardBackground)
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .padding()
}

#Preview("In Form Context") {
    @Previewable @State var icon: IconSource? = .bankLogo(.halykBank)

    return VStack(spacing: 0) {
        TextField("Name", text: .constant("My Account"))
            .padding(AppSpacing.md)

        Divider()

        IconPickerRow(selectedSource: $icon)

        Divider()

        TextField("Balance", text: .constant("1000.00"))
            .padding(AppSpacing.md)
    }
    .background(AppColors.cardBackground)
    .clipShape(.rect(cornerRadius: AppRadius.md))
    .padding()
}

#Preview("Custom Size") {
    @Previewable @State var source: IconSource? = .sfSymbol("heart.fill")

    return VStack(spacing: AppSpacing.lg) {
        IconPickerRow(
            selectedSource: $source,
            title: "Small Icon",
            iconSize: AppIconSize.sm
        )

        IconPickerRow(
            selectedSource: $source,
            title: "Medium Icon",
            iconSize: AppIconSize.lg
        )

        IconPickerRow(
            selectedSource: $source,
            title: "Large Icon",
            iconSize: AppIconSize.xxl
        )
    }
    .padding()
}
