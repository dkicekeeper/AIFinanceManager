//
//  EditableHeroSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-16
//  Phase 16: Hero-style Edit Views
//
//  Universal hero section component for edit views with:
//  - Large tappable IconView with spring animation
//  - Editable title TextField styled as H1
//  - Optional balance with NumPad TextField
//  - Inline currency picker as Menu button
//  - Optional ColorPickerRow carousel
//

import SwiftUI

/// Configuration for EditableHeroSection appearance and behavior
struct HeroConfig {
    var showBalance: Bool = false
    var showColorPicker: Bool = false
    var showCurrency: Bool = false

    static let accountHero = HeroConfig(showBalance: true, showCurrency: true)
    static let categoryHero = HeroConfig(showColorPicker: true)
    static let subscriptionHero = HeroConfig(showBalance: true, showCurrency: true)
}

/// Editable hero section for edit views with icon, title, and optional balance/color
struct EditableHeroSection: View {
    // MARK: - Bindings

    @Binding var iconSource: IconSource?
    @Binding var title: String
    @Binding var balance: String
    @Binding var currency: String
    @Binding var selectedColor: String

    // MARK: - Configuration

    let titlePlaceholder: String
    let config: HeroConfig
    let colorPalette: [String]
    let currencies: [String]

    // MARK: - State

    @State private var showingIconPicker = false
    @State private var isBalanceFocused = false
    @State private var iconScale: CGFloat = 0.8
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBalanceFieldFocused: Bool

    // MARK: - Initializer

    init(
        iconSource: Binding<IconSource?>,
        title: Binding<String>,
        balance: Binding<String> = .constant(""),
        currency: Binding<String> = .constant("USD"),
        selectedColor: Binding<String> = .constant("#3b82f6"),
        titlePlaceholder: String,
        config: HeroConfig = HeroConfig(),
        colorPalette: [String] = [
            "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
            "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
            "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
        ],
        currencies: [String] = ["USD", "EUR", "KZT", "RUB", "GBP"]
    ) {
        self._iconSource = iconSource
        self._title = title
        self._balance = balance
        self._currency = currency
        self._selectedColor = selectedColor
        self.titlePlaceholder = titlePlaceholder
        self.config = config
        self.colorPalette = colorPalette
        self.currencies = currencies
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Hero Icon
            heroIconView
                .scaleEffect(iconScale)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        iconScale = 1.0
                    }
                }

            // Title
            titleView

            // Balance (if enabled)
            if config.showBalance {
                balanceView
            }

            // Color Picker (if enabled)
            if config.showColorPicker {
                ColorPickerRow(
                    selectedColorHex: $selectedColor,
                    title: "",
                    palette: colorPalette
                )
            }
        }
        .padding(.vertical, AppSpacing.xl)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedSource: $iconSource)
        }
    }

    // MARK: - Hero Icon View

    private var heroIconView: some View {
        Button {
            HapticManager.light()
            showingIconPicker = true
        } label: {
            VStack(spacing: AppSpacing.xs) {
                if config.showColorPicker {
                    // Category icon with color
                    IconView(
                        source: iconSource ?? .sfSymbol("star.fill"),
                        style: .circle(
                            size: AppIconSize.largeButton,
                            tint: .monochrome(colorFromHex(selectedColor)),
                            backgroundColor: AppColors.surface
                        )
                    )
                } else {
                    // Account/Subscription icon with glass effect
                    if #available(iOS 18.0, *) {
                        IconView(
                            source: iconSource,
                            style: .glassHero()
                        )
                    } else {
                        IconView(
                            source: iconSource,
                            size: AppIconSize.largeButton
                        )
                    }
                }
            }
        }
//        .buttonStyle(.plain)
    }

    // MARK: - Title View

    private var titleView: some View {
        TextField(titlePlaceholder, text: $title)
            .font(AppTypography.h1)
            .multilineTextAlignment(.center)
            .focused($isTitleFocused)
            .submitLabel(.done)
    }

    // MARK: - Balance View

    private var balanceView: some View {
        VStack(spacing: AppSpacing.xs) {
            if isBalanceFocused || balance.isEmpty {
                // Editable balance field
                HStack(spacing: AppSpacing.sm) {
                    TextField("0.00", text: $balance)
                        .font(AppTypography.h4)
//                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textSecondary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($isBalanceFieldFocused)
                        .frame(maxWidth: 150)

                    if config.showCurrency {
                        currencyPicker
                    }
                }
//                .padding(.horizontal, AppSpacing.md)
//                .padding(.vertical, AppSpacing.sm)
//                .background(AppColors.secondaryBackground)
//                .clipShape(.rect(cornerRadius: AppRadius.md))
                .onTapGesture {
                    HapticManager.light()
                    isBalanceFocused = true
                    isBalanceFieldFocused = true
                }
            } else {
                // Display-only balance
                Button {
                    HapticManager.light()
                    isBalanceFocused = true
                    isBalanceFieldFocused = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if let amount = parseBalance() {
                            FormattedAmountText(
                                amount: amount,
                                currency: currency,
                                fontSize: AppTypography.h4,
                                fontWeight: .semibold,
                                color: AppColors.textSecondary
                            )
                        } else {
                            Text("0.00")
                                .font(AppTypography.h4)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if config.showCurrency {
                            Text(Formatting.currencySymbol(for: currency))
                                .font(AppTypography.h4)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isBalanceFieldFocused) { _, newValue in
            if !newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isBalanceFocused = false
                }
            }
        }
    }

    // MARK: - Currency Picker

    private var currencyPicker: some View {
        Menu {
            ForEach(currencies, id: \.self) { curr in
                Button {
                    HapticManager.selection()
                    currency = curr
                } label: {
                    HStack {
                        Text(Formatting.currencySymbol(for: curr))
                        if currency == curr {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(Formatting.currencySymbol(for: currency))
                .font(AppTypography.h4)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.accent)
        }
    }

    // MARK: - Helper Methods

    private func parseBalance() -> Double? {
        guard !balance.isEmpty else { return nil }
        return Double(balance.replacingOccurrences(of: ",", with: "."))
    }

    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Previews

#Preview("Account Hero") {
    @Previewable @State var icon: IconSource? = .bankLogo(.kaspi)
    @Previewable @State var title = "Kaspi Gold"
    @Previewable @State var balance = "125000.50"
    @Previewable @State var currency = "KZT"
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: "Account Name",
            config: .accountHero
        )
    }
    .padding()
}

#Preview("Category Hero") {
    @Previewable @State var icon: IconSource? = .sfSymbol("fork.knife")
    @Previewable @State var title = "Food & Drinks"
    @Previewable @State var balance = ""
    @Previewable @State var currency = "USD"
    @Previewable @State var color = "#ec4899"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: "Category Name",
            config: .categoryHero
        )
    }
    .padding()
}

#Preview("Subscription Hero") {
    @Previewable @State var icon: IconSource? = .brandService("netflix")
    @Previewable @State var title = "Netflix Premium"
    @Previewable @State var balance = "15.99"
    @Previewable @State var currency = "USD"
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: "Subscription Name",
            config: .subscriptionHero
        )
    }
    .padding()
}

#Preview("Empty State") {
    @Previewable @State var icon: IconSource? = nil
    @Previewable @State var title = ""
    @Previewable @State var balance = ""
    @Previewable @State var currency = "USD"
    @Previewable @State var color = "#3b82f6"

    return ScrollView {
        EditableHeroSection(
            iconSource: $icon,
            title: $title,
            balance: $balance,
            currency: $currency,
            selectedColor: $color,
            titlePlaceholder: "Enter name...",
            config: .accountHero
        )
    }
    .padding()
}

#Preview("Interactive Demo") {
    struct InteractiveDemoView: View {
        @State private var icon: IconSource? = .sfSymbol("star.fill")
        @State private var title = "My Category"
        @State private var balance = "1000"
        @State private var currency = "USD"
        @State private var color = "#3b82f6"
        @State private var selectedConfig: HeroConfig = .categoryHero

        var body: some View {
            VStack(spacing: AppSpacing.xxl) {
                EditableHeroSection(
                    iconSource: $icon,
                    title: $title,
                    balance: $balance,
                    currency: $currency,
                    selectedColor: $color,
                    titlePlaceholder: "Enter name",
                    config: selectedConfig
                )

                Divider()

                VStack(spacing: AppSpacing.md) {
                    Text("Configuration")
                        .font(AppTypography.h4)

                    Button("Account Hero") {
                        selectedConfig = .accountHero
                        icon = .bankLogo(.kaspi)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Category Hero") {
                        selectedConfig = .categoryHero
                        icon = .sfSymbol("fork.knife")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Subscription Hero") {
                        selectedConfig = .subscriptionHero
                        icon = .brandService("netflix")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    return InteractiveDemoView()
}
