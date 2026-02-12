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
            VStack(spacing: 0) {
                // Segmented Picker
                Picker("", selection: $pickerMode) {
                    ForEach(PickerMode.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(AppSpacing.lg)

                // Content
                switch pickerMode {
                case .icons:
                    IconsTabView(selectedSource: $selectedSource)
                case .logos:
                    LogosTabView(selectedSource: $selectedSource)
                }
            }
            .navigationTitle(String(localized: "iconPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "button.done")) {
                        HapticManager.light()
                        dismiss()
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

    private var popularBanks: [BankLogo] {
        [.alatauCityBank, .halykBank, .kaspi, .homeCredit, .eurasian, .forte, .jusan]
    }

    private var otherBanks: [BankLogo] {
        BankLogo.allCases.filter { $0 != .none && !popularBanks.contains($0) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isSearching {
                // Результаты поиска logo.dev - просто показываем введенный текст
                OnlineSearchResultsView(
                    searchText: searchText,
                    selectedSource: $selectedSource
                )
            } else {
                // Локальные банки
                List {
                    // Популярные банки
                    Section {
                        ForEach(popularBanks) { bank in
                            BankLogoRow(
                                bank: bank,
                                isSelected: selectedSource == .bankLogo(bank),
                                onSelect: {
                                    HapticManager.selection()
                                    selectedSource = .bankLogo(bank)
                                    dismiss()
                                }
                            )
                        }
                    } header: {
                        Text(String(localized: "iconPicker.popularBanks"))
                    }

                    // Другие банки
                    Section {
                        ForEach(otherBanks) { bank in
                            BankLogoRow(
                                bank: bank,
                                isSelected: selectedSource == .bankLogo(bank),
                                onSelect: {
                                    HapticManager.selection()
                                    selectedSource = .bankLogo(bank)
                                    dismiss()
                                }
                            )
                        }
                    } header: {
                        Text(String(localized: "iconPicker.otherBanks"))
                    }

                    // Без логотипа
                    Section {
                        BankLogoRow(
                            bank: .none,
                            isSelected: selectedSource == .bankLogo(.none) || selectedSource == nil,
                            onSelect: {
                                HapticManager.selection()
                                selectedSource = nil
                                dismiss()
                            }
                        )
                    }
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
