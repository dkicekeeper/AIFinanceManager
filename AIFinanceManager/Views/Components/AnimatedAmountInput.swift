//
//  AnimatedAmountInput.swift
//  AIFinanceManager
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Animated input components for EditableHeroSection:
//  - AnimatedAmountInput: hero-style balance input with per-digit spring animations
//  - AnimatedTitleInput: hero-style name input with soft character animations
//
//  Intentionally excludes currency conversion (AmountInputView handles that).
//

import SwiftUI

// MARK: - AnimatedAmountInput

/// Hero-style balance input with per-digit spring + wobble animations.
/// Displays formatted number with animated characters; no currency conversion.
///
/// Usage:
/// ```swift
/// AnimatedAmountInput(amount: $balance)
/// AnimatedAmountInput(amount: $balance, baseFontSize: 40, color: AppColors.income)
/// ```
struct AnimatedAmountInput: View {
    @Binding var amount: String
    var baseFontSize: CGFloat = 48
    var color: Color = AppColors.textPrimary

    @FocusState private var isFocused: Bool
    @State private var displayAmount: String = "0"
    @State private var currentFontSize: CGFloat = 48
    @State private var containerWidth: CGFloat = 0

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.decimalSeparator = "."
        return f
    }()

    private static let largeNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        return f
    }()

    private static let measureFont: UIFont =
        UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)
    private static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]

    var body: some View {
        VStack(spacing: 0) {
            // Amount display — tap to focus
            Button {
                HapticManager.light()
                isFocused = true
            } label: {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: AppSpacing.xs) {
                        Text(displayAmount)
                            .font(.custom("Inter", size: currentFontSize).weight(.bold))
                            .contentTransition(.numericText())
                            .foregroundStyle(isPlaceholder ? AppColors.textTertiary : color)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayAmount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        if isFocused {
                            BlinkingCursor(height: cursorHeight)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Hidden TextField — actual input source
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    updateDisplayAmount(newValue)
                }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard containerWidth != newWidth else { return }
            containerWidth = newWidth
            updateFontSize(for: newWidth)
        }
        .onChange(of: displayAmount) { _, _ in
            if containerWidth > 0 {
                updateFontSize(for: containerWidth)
            }
        }
        .onAppear {
            currentFontSize = baseFontSize
            updateDisplayAmount(amount)
        }
    }

    // MARK: - Computed

    private var isPlaceholder: Bool {
        amount.isEmpty || amount == "0"
    }

    private var cursorHeight: CGFloat {
        // Scale cursor proportionally to font size
        AppSize.cursorHeight * (currentFontSize / 36)
    }

    // MARK: - Formatting

    private func cleanedRaw(_ text: String) -> String {
        text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func updateDisplayAmount(_ text: String) {
        let cleaned = cleanedRaw(text)

        let newDisplay: String
        if cleaned.isEmpty {
            newDisplay = "0"
        } else if let decimal = Decimal(string: cleaned) {
            let number = NSDecimalNumber(decimal: decimal)
            if number.compare(NSDecimalNumber.zero) == .orderedSame {
                newDisplay = "0"
            } else if let formatted = Self.formatter.string(from: number) {
                newDisplay = formatted
            } else {
                newDisplay = formatLargeNumber(decimal)
            }
        } else {
            newDisplay = cleaned
        }

        displayAmount = newDisplay
    }

    private func formatLargeNumber(_ decimal: Decimal) -> String {
        if let s = Self.largeNumberFormatter.string(from: NSDecimalNumber(decimal: decimal)) { return s }
        let string = String(describing: decimal)
        guard string.contains(".") else { return groupDigits(string) }
        let parts = string.components(separatedBy: ".")
        return "\(groupDigits(parts[0])).\(parts[1].prefix(2))"
    }

    private func groupDigits(_ s: String) -> String {
        var result = ""
        for (i, char) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { result = " " + result }
            result = String(char) + result
        }
        return result
    }

    // MARK: - Font Sizing

    private func updateFontSize(for width: CGFloat) {
        guard width > 0 else { return }
        if displayAmount == "0" {
            currentFontSize = baseFontSize
            return
        }

        let maxWidth = width - (AppSpacing.lg * 2) - 20
        let textSize = (displayAmount as NSString).size(withAttributes: Self.measureAttributes)
        let totalWidth = textSize.width

        let newSize: CGFloat
        if totalWidth > maxWidth && maxWidth > 0 {
            let scale = maxWidth / totalWidth
            newSize = max(24, min(baseFontSize, baseFontSize * scale))
        } else {
            newSize = baseFontSize
        }

        if abs(currentFontSize - newSize) > 0.5 {
            currentFontSize = newSize
        }
    }

}

// MARK: - AnimatedTitleInput

/// Hero-style name/title input with soft scale+fade character animations.
/// Renders animated text display over a hidden TextField.
///
/// Usage:
/// ```swift
/// AnimatedTitleInput(text: $title, placeholder: String(localized: "account.namePlaceholder"))
/// AnimatedTitleInput(text: $title, placeholder: "...", font: AppTypography.h2)
/// ```
struct AnimatedTitleInput: View {
    @Binding var text: String
    let placeholder: String
    var font: Font = AppTypography.h1
    var color: Color = AppColors.textPrimary
    var alignment: TextAlignment = .center

    @FocusState private var isFocused: Bool

    // Placeholder скрывается когда есть текст ИЛИ поле сфокусировано
    private var showPlaceholder: Bool {
        text.isEmpty && !isFocused
    }

    // Курсор виден при фокусе (в том числе при пустом тексте)
    private var showCursor: Bool {
        isFocused
    }

    var body: some View {
        ZStack {
            // Placeholder — hidden when focused or text is present
            if showPlaceholder {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(alignment)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // Animated text + cursor
            HStack(spacing: 0) {
                if alignment == .center { Spacer() }
                HStack(spacing: 1) {
                    Text(text.isEmpty ? "" : text)
                        .font(font)
                        .foregroundStyle(color)
                        .contentTransition(.interpolate)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text)

                    if showCursor {
                        BlinkingCursor(height: AppSize.cursorHeightLarge)
                            .transition(.opacity)
                    }
                }
                if alignment == .center { Spacer() }
            }
            .allowsHitTesting(false)

            // Hidden TextField — actual input source
            TextField("", text: $text)
                .font(font)
                .multilineTextAlignment(alignment)
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .submitLabel(.done)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.light()
            isFocused = true
        }
        .animation(.easeInOut(duration: 0.15), value: showPlaceholder)
        .animation(.easeInOut(duration: 0.15), value: showCursor)
        .onAppear {
            // No character tracking needed anymore
        }
    }
}

// MARK: - Previews

#Preview("Animated Amount Input") {
    struct Demo: View {
        @State private var amount = ""
        var body: some View {
            VStack(spacing: AppSpacing.xl) {
                Text("Balance").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                AnimatedAmountInput(amount: $amount)
                    .padding(.horizontal, AppSpacing.xl)

                Text("Expense").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                AnimatedAmountInput(
                    amount: $amount,
                    baseFontSize: 40,
                    color: AppColors.expense
                )
                .padding(.horizontal, AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
    }
    return Demo()
}

#Preview("Animated Title Input") {
    struct Demo: View {
        @State private var title = ""
        var body: some View {
            VStack(spacing: AppSpacing.xl) {
                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "account.namePlaceholder")
                )
                .padding(.horizontal, AppSpacing.xl)

                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "category.namePlaceholder"),
                    font: AppTypography.h2,
                    color: AppColors.accent
                )
                .padding(.horizontal, AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
    }
    return Demo()
}

#Preview("Hero Section Combined") {
    struct Demo: View {
        @State private var title = "Kaspi Gold"
        @State private var amount = "125000"
        var body: some View {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: AppIconSize.largeButton))
                    .foregroundStyle(AppColors.accent)

                AnimatedTitleInput(
                    text: $title,
                    placeholder: String(localized: "account.namePlaceholder")
                )

                AnimatedAmountInput(amount: $amount)

                Text("KZT")
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.xl)
        }
    }
    return Demo()
}
