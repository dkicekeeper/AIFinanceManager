//
//  AmountInputView.swift
//  AIFinanceManager
//
//  Large centered amount input with currency selector.
//  Supports copy/paste via long-press context menu.
//

import SwiftUI

struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    let baseCurrency: String
    var onAmountChange: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var displayAmount: String = "0"
    @State private var previousAmount: String = ""
    @State private var previousRawAmount: String = ""
    @State private var animatedCharacters: [AnimatedChar] = []
    @State private var currentFontSize: CGFloat = 56
    @State private var containerWidth: CGFloat = 0

    // MARK: - Currency Conversion
    @State private var convertedAmount: Double?
    @State private var conversionTask: Task<Void, Never>?

    // Shared formatters — created once, reused on every call
    private let displayFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.decimalSeparator = "."
        return f
    }()

    private static let convertedAmountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Amount display — tap to focus, long-press for copy/paste
            Button {
                isFocused = true
            } label: {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: spacingForFontSize(currentFontSize)) {
                        ForEach(animatedCharacters) { charState in
                            AnimatedDigit(
                                character: charState.character,
                                isNew: charState.isNew,
                                fontSize: currentFontSize,
                                color: errorMessage != nil ? .red : .primary
                            )
                            .id("\(charState.id)-\(charState.character)")
                        }

                        if isFocused {
                            BlinkingCursor()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    copyAmount()
                } label: {
                    Label(String(localized: "button.copy"), systemImage: "doc.on.doc")
                }

                if UIPasteboard.general.hasStrings {
                    Button {
                        pasteAmount()
                    } label: {
                        Label(String(localized: "button.paste"), systemImage: "doc.on.clipboard")
                    }
                }
            }

            // Converted amount in base currency
            convertedAmountView

            // Hidden TextField captures keyboard input
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    updateDisplayAmount(newValue)
                    onAmountChange?(newValue)
                    updateConvertedAmountDebounced()
                }

            // Currency selector (centred)
            CurrencySelectorView(selectedCurrency: $selectedCurrency)
                .onChange(of: selectedCurrency) { _, _ in
                    Task { await updateConvertedAmount() }
                }

            // Validation error
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppSpacing.lg)
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
            updateDisplayAmount(amount)
            previousAmount = displayAmount
            let cleaned = Self.cleanAmountString(amount)
            previousRawAmount = cleaned.isEmpty ? "0" : cleaned
            animatedCharacters = displayAmount.map { char in
                AnimatedChar(id: UUID(), character: char, isNew: false)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
        .task {
            await updateConvertedAmount()
        }
    }

    // MARK: - Converted Amount View

    @ViewBuilder
    private var convertedAmountView: some View {
        if shouldShowConversion {
            HStack(spacing: AppSpacing.xs) {
                Text("currency.conversion.approximate")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textSecondary)

                if let converted = convertedAmount {
                    Text(formatConvertedAmount(converted))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textSecondary)

                    Text(Formatting.currencySymbol(for: baseCurrency))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Currency Conversion Logic

    private var shouldShowConversion: Bool {
        guard selectedCurrency != baseCurrency else { return false }
        guard let numericAmount = parseAmount(amount), numericAmount > 0 else { return false }
        return true
    }

    private func parseAmount(_ text: String) -> Double? {
        Double(Self.cleanAmountString(text))
    }

    private func formatConvertedAmount(_ value: Double) -> String {
        Self.convertedAmountFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func updateConvertedAmountDebounced() {
        conversionTask?.cancel()
        conversionTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await updateConvertedAmount()
        }
    }

    @MainActor
    private func updateConvertedAmount() async {
        guard selectedCurrency != baseCurrency else {
            convertedAmount = nil
            return
        }

        guard let numericAmount = parseAmount(amount), numericAmount > 0 else {
            convertedAmount = nil
            return
        }

        // Fast path: use cached rate
        if let syncConverted = CurrencyConverter.convertSync(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            convertedAmount = syncConverted
            return
        }

        // Slow path: fetch rate from network
        if let asyncConverted = await CurrencyConverter.convert(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            convertedAmount = asyncConverted
        }
    }

    // MARK: - Copy / Paste

    private func copyAmount() {
        UIPasteboard.general.string = amount.isEmpty ? "0" : amount
    }

    private func pasteAmount() {
        guard let clipboardText = UIPasteboard.general.string else { return }
        let cleaned = Self.cleanAmountString(clipboardText)
        guard !cleaned.isEmpty, Double(cleaned) != nil else { return }
        amount = cleaned
    }

    // MARK: - Display Amount Helpers

    /// Normalises decimal separator and strips all non-numeric characters.
    /// Single source of truth — replaces three previously duplicated blocks.
    private static func cleanAmountString(_ text: String) -> String {
        text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
    }

    private func updateDisplayAmount(_ text: String) {
        let cleaned = Self.cleanAmountString(text)

        let newDisplayAmount: String
        if cleaned.isEmpty {
            newDisplayAmount = "0"
        } else if let decimal = Decimal(string: cleaned) {
            let number = NSDecimalNumber(decimal: decimal)
            if number.compare(NSDecimalNumber.zero) == .orderedSame {
                newDisplayAmount = "0"
            } else if let formatted = displayFormatter.string(from: number) {
                newDisplayAmount = formatted
            } else {
                newDisplayAmount = formatLargeNumber(decimal)
            }
        } else {
            newDisplayAmount = cleaned
        }

        updateAnimatedCharacters(newAmount: newDisplayAmount, rawAmount: cleaned)
        displayAmount = newDisplayAmount
    }

    private func formatLargeNumber(_ decimal: Decimal) -> String {
        if let formatted = Self.convertedAmountFormatter.string(from: NSDecimalNumber(decimal: decimal)) {
            return formatted
        }

        let string = String(describing: decimal)
        if string.contains(".") {
            let parts = string.components(separatedBy: ".")
            let intPart = groupDigits(parts[0])
            let fracPart = parts.count > 1 ? String(parts[1].prefix(2)) : ""
            return fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
        }
        return groupDigits(string)
    }

    private func groupDigits(_ integerString: String) -> String {
        var result = ""
        var count = 0
        for char in integerString.reversed() {
            if count > 0 && count % 3 == 0 { result = " " + result }
            result = String(char) + result
            count += 1
        }
        return result
    }

    private func spacingForFontSize(_ size: CGFloat) -> CGFloat {
        max(0.5, (size / 56) * 2)
    }

    private func updateFontSize(for width: CGFloat) {
        if displayAmount == "0" {
            currentFontSize = 56
            return
        }

        guard width > 0 else { return }

        let testText = displayAmount.isEmpty ? "0" : displayAmount
        let maxWidth = width - (AppSpacing.lg * 2) - 20
        let baseSize: CGFloat = 56

        let charCount = testText.count
        let totalSpacing = CGFloat(max(0, charCount - 1)) * spacingForFontSize(baseSize)
        let testFont = UIFont(name: "Overpass-Bold", size: baseSize)
            ?? UIFont.systemFont(ofSize: baseSize, weight: .bold)
        let textSize = (testText as NSString).size(withAttributes: [.font: testFont])
        let totalWidth = textSize.width + totalSpacing

        let newFontSize: CGFloat
        if totalWidth > maxWidth && maxWidth > 0 {
            let scaleFactor = maxWidth / totalWidth
            newFontSize = max(24, min(baseSize, baseSize * scaleFactor))
        } else {
            newFontSize = baseSize
        }

        if abs(currentFontSize - newFontSize) > 0.5 {
            currentFontSize = newFontSize
        }
    }

    private func updateAnimatedCharacters(newAmount: String, rawAmount: String) {
        let newRawChars = Array(rawAmount)
        let previousRawChars = Array(previousRawAmount)

        var changedRawPositions: Set<Int> = []
        let maxLength = max(newRawChars.count, previousRawChars.count)
        for i in 0..<maxLength {
            guard i < newRawChars.count else { continue }
            if i >= previousRawChars.count || newRawChars[i] != previousRawChars[i] {
                changedRawPositions.insert(i)
            }
        }

        let formattedChars = Array(newAmount)
        var updated: [AnimatedChar] = []
        var rawIndex = 0

        for (formattedIndex, formattedChar) in formattedChars.enumerated() {
            if formattedChar == " " {
                let charId = formattedIndex < animatedCharacters.count
                    ? animatedCharacters[formattedIndex].id
                    : UUID()
                updated.append(AnimatedChar(id: charId, character: formattedChar, isNew: false))
                continue
            }

            let isNew: Bool
            let charId: UUID
            if rawIndex < newRawChars.count {
                if changedRawPositions.contains(rawIndex) {
                    isNew = true
                    charId = UUID()
                } else {
                    isNew = false
                    charId = (formattedIndex < animatedCharacters.count
                        && animatedCharacters[formattedIndex].character == formattedChar)
                        ? animatedCharacters[formattedIndex].id
                        : UUID()
                }
                rawIndex += 1
            } else {
                isNew = false
                charId = UUID()
            }

            updated.append(AnimatedChar(id: charId, character: formattedChar, isNew: isNew))
        }

        animatedCharacters = updated
        previousAmount = newAmount
        previousRawAmount = rawAmount
    }
}

// AnimatedChar, AnimatedDigit, BlinkingCursor, ContainerWidthKey
// are defined in Views/Components/AnimatedInputComponents.swift

#Preview("Amount Input - Empty") {
    @Previewable @State var amount = ""
    @Previewable @State var currency = "KZT"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT"
    )
}

#Preview("Amount Input - With Value") {
    @Previewable @State var amount = "1234.56"
    @Previewable @State var currency = "USD"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT"
    )
}

#Preview("Amount Input - Error") {
    @Previewable @State var amount = "abc"
    @Previewable @State var currency = "EUR"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: "Введите корректную сумму",
        baseCurrency: "KZT"
    )
}
