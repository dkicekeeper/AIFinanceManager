//
//  IconPickerView.swift
//  AIFinanceManager
//
//  Unified icon/logo picker with segmented control for all entities
//

import SwiftUI

struct IconPickerView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    @State private var pickerMode: PickerMode = .icons

    enum PickerMode: String, CaseIterable {
        case icons
        case logos

        var localizedTitle: String {
            switch self {
            case .icons: return String(localized: "iconPicker.iconsTab")
            case .logos: return String(localized: "iconPicker.logosTab")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // Content
                switch pickerMode {
                case .icons:
                    IconsTabView(selectedSource: $selectedSource)
                case .logos:
                    LogosTabView(selectedSource: $selectedSource)
                }
            }
            .safeAreaInset(edge: .top) {
                SegmentedPickerView(
                    title: "",
                    selection: $pickerMode,
                    options: PickerMode.allCases.map { (label: $0.localizedTitle, value: $0) }
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.backgroundPrimary)
            }
            .navigationTitle(String(localized: "iconPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: AppIconSize.md, weight: .semibold))
                    }
                }
            }
        }
    }
}

// MARK: - Icons Tab

private struct IconsTabView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    private let iconCategories: [(String, [String])] = [
        (String(localized: "iconPicker.frequentlyUsed"), ["banknote.fill", "cart.fill", "car.fill", "bag.fill", "fork.knife", "house.fill", "briefcase.fill", "heart.fill", "airplane", "gift.fill", "creditcard.fill", "tv.fill", "book.fill", "star.fill", "bolt.fill", "flame.fill"]),
        (String(localized: "iconPicker.foodAndDrinks"), ["fork.knife", "cup.and.saucer.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "fish.fill", "leaf.fill", "mug.fill"]),
        (String(localized: "iconPicker.transport"), ["car.fill", "bus.fill", "airplane", "tram.fill", "bicycle", "scooter", "ferry.fill", "fuelpump.fill"]),
        (String(localized: "iconPicker.shopping"), ["bag.fill", "cart.fill", "creditcard.fill", "handbag.fill", "tshirt.fill", "giftcard.fill", "basket.fill", "tag.fill"]),
        (String(localized: "iconPicker.entertainment"), ["film.fill", "gamecontroller.fill", "music.note", "theatermasks.fill", "paintpalette.fill", "book.fill", "sportscourt.fill", "figure.walk"]),
        (String(localized: "iconPicker.health"), ["cross.case.fill", "heart.text.square.fill", "bandage.fill", "syringe.fill", "cross.fill", "eye.fill", "waveform.path.ecg", "figure.run"]),
        (String(localized: "iconPicker.homeAndUtilities"), ["house.fill", "key.fill", "chair.fill", "bed.double.fill", "lightbulb.fill", "sparkles", "sofa.fill", "shower.fill"]),
        (String(localized: "iconPicker.moneyAndFinance"), ["banknote.fill", "dollarsign.circle.fill", "creditcard.fill", "building.columns.fill", "chart.bar.fill", "rublesign.circle.fill", "eurosign.circle.fill"])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                ForEach(iconCategories, id: \.0) { category in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Text(category.0)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, AppSpacing.lg)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.lg), count: 6),
                            spacing: AppSpacing.lg
                        ) {
                            ForEach(category.1, id: \.self) { iconName in
                                IconButton(
                                    iconName: iconName,
                                    isSelected: selectedSource == .sfSymbol(iconName),
                                    onTap: {
                                        HapticManager.selection()
                                        selectedSource = .sfSymbol(iconName)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                }
            }
            .padding(.vertical, AppSpacing.lg)
        }
    }
}

// MARK: - Icon Button

private struct IconButton: View {
    let iconName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: iconName)
                .font(.system(size: AppIconSize.lg))
                .foregroundStyle(isSelected ? .white : AppColors.textPrimary)
                .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                .background(isSelected ? AppColors.accent : AppColors.surface)
                .clipShape(.rect(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logos Tab

private struct LogosTabView: View {
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    // Категории логотипов для будущего расширения
    private let logoCategories: [(String, [BankLogo])] = [
        (String(localized: "iconPicker.banks"), [
            .alatauCityBank, .halykBank, .kaspi, .homeCredit,
            .eurasian, .forte, .jusan, .otbasy, .centerCredit,
            .bereke, .alfaBank, .freedom, .sber, .vtb,
            .tbank, .rbk, .nurBank, .asiaCredit,
            .tengri, .brk, .citi, .ebr, .bankOfChina,
            .moscowBank, .icbc, .shinhan, .kbo, .atf
        ])
        // TODO: Добавить категории:
        // - Развлечения (YouTube, Netflix, HBO, Disney+)
        // - Музыка (Spotify, Apple Music, Yandex Music)
        // - Сервисы (iCloud, Google Drive, Dropbox)
    ]

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isSearching {
                // Результаты поиска logo.dev
                OnlineSearchResultsView(
                    searchText: searchText,
                    selectedSource: $selectedSource
                )
            } else {
                // Grid логотипов
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                        ForEach(logoCategories, id: \.0) { category in
                            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                Text(category.0)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, AppSpacing.lg)

                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.lg), count: 4),
                                    spacing: AppSpacing.lg
                                ) {
                                    ForEach(category.1) { bank in
                                        LogoButton(
                                            bank: bank,
                                            isSelected: selectedSource == .bankLogo(bank),
                                            onTap: {
                                                HapticManager.selection()
                                                selectedSource = .bankLogo(bank)
                                                dismiss()
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, AppSpacing.lg)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.lg)
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: String(localized: "iconPicker.searchOnline")
        )
    }
}

// MARK: - Logo Button

private struct LogoButton: View {
    let bank: BankLogo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            BrandLogoDisplayView(
                iconSource: .bankLogo(bank),
                size: AppIconSize.xxxl
            )
            .frame(width: AppIconSize.coin, height: AppIconSize.coin)
            .background(isSelected ? AppColors.accent.opacity(0.1) : AppColors.surface)
            .clipShape(.rect(cornerRadius: AppRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Online Search Results View

private struct OnlineSearchResultsView: View {
    let searchText: String
    @Binding var selectedSource: IconSource?
    @Environment(\.dismiss) private var dismiss

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        List {
            Section {
                // Показываем preview логотипа для введенного текста
                OnlineLogoRow(
                    brandName: trimmedSearch,
                    isSelected: selectedSource == .brandService(trimmedSearch),
                    onSelect: {
                        HapticManager.selection()
                        selectedSource = .brandService(trimmedSearch)
                        dismiss()
                    }
                )
            } header: {
                Text(String(localized: "iconPicker.searchResults"))
                    .foregroundStyle(AppColors.textPrimary)
            } footer: {
                Text("Введите домен бренда (например: netflix.com)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

// MARK: - Online Logo Row

private struct OnlineLogoRow: View {
    let brandName: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.md) {
                // Logo preview
                BrandLogoDisplayView(
                    iconSource: .brandService(brandName),
                    size: AppIconSize.xxl
                )

                Text(brandName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Icons Tab") {
    @Previewable @State var source: IconSource? = .sfSymbol("star.fill")
    return IconPickerView(selectedSource: $source)
}

#Preview("Logos Tab") {
    @Previewable @State var source: IconSource? = .bankLogo(.kaspi)
    return IconPickerView(selectedSource: $source)
}
