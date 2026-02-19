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
    @State private var previousRawAmount: String = "0"
    @State private var animatedCharacters: [AnimatedChar] = []
    @State private var currentFontSize: CGFloat = 48
    @State private var containerWidth: CGFloat = 0

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.decimalSeparator = "."
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Animated display + blinking cursor
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: spacingForFontSize(currentFontSize)) {
                    ForEach(animatedCharacters) { charState in
                        AnimatedDigit(
                            character: charState.character,
                            isNew: charState.isNew,
                            fontSize: currentFontSize,
                            color: isPlaceholder ? AppColors.textTertiary : color
                        )
                        .id("\(charState.id)-\(charState.character)")
                    }
                    if isFocused {
                        BlinkingCursor(height: cursorHeight)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.light()
                isFocused = true
            }

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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ContainerWidthKey.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(ContainerWidthKey.self) { width in
            if containerWidth != width {
                containerWidth = width
                updateFontSize(for: width)
            }
        }
        .onChange(of: displayAmount) { _, _ in
            if containerWidth > 0 {
                updateFontSize(for: containerWidth)
            }
        }
        .onAppear {
            currentFontSize = baseFontSize
            updateDisplayAmount(amount)
            previousRawAmount = cleanedRaw(amount)
            animatedCharacters = Array(displayAmount).map { char in
                AnimatedChar(id: UUID(), character: char, isNew: false)
            }
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
            } else if let formatted = formatter.string(from: number) {
                newDisplay = formatted
            } else {
                newDisplay = formatLargeNumber(decimal)
            }
        } else {
            newDisplay = cleaned
        }

        updateAnimatedCharacters(newDisplay: newDisplay, rawAmount: cleaned)
        displayAmount = newDisplay
    }

    private func formatLargeNumber(_ decimal: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        if let s = f.string(from: NSDecimalNumber(decimal: decimal)) { return s }

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

    private func spacingForFontSize(_ size: CGFloat) -> CGFloat {
        max(0.5, (size / 56) * 2)
    }

    private func updateFontSize(for width: CGFloat) {
        guard width > 0 else { return }
        if displayAmount == "0" {
            currentFontSize = baseFontSize
            return
        }

        let maxWidth = width - (AppSpacing.lg * 2) - 20
        let charCount = displayAmount.count
        let baseSpacing = spacingForFontSize(baseFontSize)
        let totalSpacing = CGFloat(max(0, charCount - 1)) * baseSpacing
        let testFont = UIFont(name: "Overpass-Bold", size: baseFontSize)
            ?? UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
        let textSize = (displayAmount as NSString).size(withAttributes: [.font: testFont])
        let totalWidth = textSize.width + totalSpacing

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

    // MARK: - Animation Tracking

    private func updateAnimatedCharacters(newDisplay: String, rawAmount: String) {
        let newRaw = Array(rawAmount)
        let prevRaw = Array(previousRawAmount)

        var changedPositions = Set<Int>()
        let maxLen = max(newRaw.count, prevRaw.count)
        for i in 0..<maxLen {
            if i >= prevRaw.count || i >= newRaw.count || newRaw[i] != prevRaw[i] {
                if i < newRaw.count { changedPositions.insert(i) }
            }
        }

        let formatted = Array(newDisplay)
        var updated: [AnimatedChar] = []
        var rawIndex = 0

        for (formIdx, char) in formatted.enumerated() {
            if char == " " {
                let id = formIdx < animatedCharacters.count ? animatedCharacters[formIdx].id : UUID()
                updated.append(AnimatedChar(id: id, character: char, isNew: false))
                continue
            }

            let isNew: Bool
            let charId: UUID
            if rawIndex < newRaw.count {
                isNew = changedPositions.contains(rawIndex)
                if !isNew && formIdx < animatedCharacters.count && animatedCharacters[formIdx].character == char {
                    charId = animatedCharacters[formIdx].id
                } else {
                    charId = isNew ? UUID() : UUID()
                }
                rawIndex += 1
            } else {
                isNew = false
                charId = UUID()
            }

            updated.append(AnimatedChar(id: charId, character: char, isNew: isNew))
        }

        animatedCharacters = updated
        previousRawAmount = rawAmount
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
    @State private var animatedCharacters: [AnimatedChar] = []
    @State private var previousText: String = ""

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
            // Placeholder — скрывается при фокусе
            if showPlaceholder {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(alignment)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // Animated characters + cursor
            HStack(spacing: 0) {
                if alignment == .center { Spacer() }
                HStack(spacing: 1) {
                    ForEach(animatedCharacters) { charState in
                        AnimatedTitleChar(
                            character: charState.character,
                            isNew: charState.isNew,
                            font: font,
                            color: color
                        )
                        .id("\(charState.id)-\(charState.character)")
                    }
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
                .onChange(of: text) { _, newValue in
                    updateAnimatedCharacters(newText: newValue)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.light()
            isFocused = true
        }
        .animation(.easeInOut(duration: 0.15), value: showPlaceholder)
        .animation(.easeInOut(duration: 0.15), value: showCursor)
        .onAppear {
            previousText = text
            animatedCharacters = Array(text).map { char in
                AnimatedChar(id: UUID(), character: char, isNew: false)
            }
        }
    }

    // MARK: - Animation Tracking

    private func updateAnimatedCharacters(newText: String) {
        let newChars = Array(newText)
        let prevChars = Array(previousText)

        var updated: [AnimatedChar] = []

        for (i, char) in newChars.enumerated() {
            // Символ новый если добавлен в конец или изменён
            let isNew = i >= prevChars.count || prevChars[i] != char
            let charId: UUID
            if !isNew && i < animatedCharacters.count && animatedCharacters[i].character == char {
                charId = animatedCharacters[i].id
            } else {
                charId = UUID()
            }
            updated.append(AnimatedChar(id: charId, character: char, isNew: isNew))
        }

        animatedCharacters = updated
        previousText = newText
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
