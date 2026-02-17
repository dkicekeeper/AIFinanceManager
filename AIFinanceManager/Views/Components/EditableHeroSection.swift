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
    @State private var displayBalance: String = ""
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
        .buttonStyle(.plain)
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
        VStack(spacing: AppSpacing.sm) {
            if isBalanceFocused || balance.isEmpty {
                // Editable balance field
                TextField("0", text: $displayBalance)
                    .font(AppTypography.h2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isBalanceFieldFocused)
                    .onChange(of: displayBalance) { _, newValue in
                        updateBalanceFromDisplay(newValue)
                    }
                    .onAppear {
                        if !balance.isEmpty {
                            displayBalance = formatBalanceForEditing(balance)
                        }
                    }
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
                    displayBalance = formatBalanceForEditing(balance)
                } label: {
                    if let amount = parseBalance() {
                        Text(formatBalanceWithoutSymbol(amount))
                            .font(AppTypography.h2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text("0")
                            .font(AppTypography.h2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            if config.showCurrency {
                currencyPicker
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
        CurrencySelectorView(
            selectedCurrency: $currency,
            availableCurrencies: currencies
        )
    }

    // MARK: - Helper Methods

    private func parseBalance() -> Double? {
        guard !balance.isEmpty else { return nil }
        return Double(balance.replacingOccurrences(of: ",", with: "."))
    }

    private func formatBalanceWithoutSymbol(_ amount: Double) -> String {
        let config = AmountDisplayConfiguration.shared
        let numberFormatter = config.makeNumberFormatter()

        // Check if we should show decimals
        let hasDecimals = amount.truncatingRemainder(dividingBy: 1) != 0

        if !config.showDecimalsWhenZero && !hasDecimals {
            numberFormatter.minimumFractionDigits = 0
            numberFormatter.maximumFractionDigits = 0
        }

        guard let formattedAmount = numberFormatter.string(from: NSNumber(value: amount)) else {
            return String(format: "%.2f", amount)
        }

        return formattedAmount
    }

    private func formatBalanceForEditing(_ rawBalance: String) -> String {
        // Remove any non-numeric characters except decimal separator
        let cleanedString = rawBalance.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(cleanedString) else { return rawBalance }

        let config = AmountDisplayConfiguration.shared
        let numberFormatter = config.makeNumberFormatter()

        // Check if we should show decimals
        let hasDecimals = amount.truncatingRemainder(dividingBy: 1) != 0

        if !config.showDecimalsWhenZero && !hasDecimals {
            numberFormatter.minimumFractionDigits = 0
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: amount)) ?? rawBalance
    }

    private func updateBalanceFromDisplay(_ displayValue: String) {
        // Remove thousand separators and convert decimal separator
        let cleanedString = displayValue
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        // Validate that it's a valid number format
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
        let characterSet = CharacterSet(charactersIn: cleanedString)

        guard allowedCharacters.isSuperset(of: characterSet) else { return }

        // Count decimal points
        let decimalCount = cleanedString.filter { $0 == "." }.count
        guard decimalCount <= 1 else { return }

        // Update the binding with clean value
        balance = cleanedString

        // Reformat display with thousand separators
        if let amount = Double(cleanedString) {
            let config = AmountDisplayConfiguration.shared
            let numberFormatter = config.makeNumberFormatter()

            // Check if we should show decimals
            let hasDecimals = amount.truncatingRemainder(dividingBy: 1) != 0

            if !config.showDecimalsWhenZero && !hasDecimals {
                numberFormatter.minimumFractionDigits = 0
                numberFormatter.maximumFractionDigits = 0
            }

            if let formatted = numberFormatter.string(from: NSNumber(value: amount)) {
                displayBalance = formatted
            }
        }
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
