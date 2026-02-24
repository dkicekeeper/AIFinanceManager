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
    @State private var currentFontSize: CGFloat = 56
    @State private var containerWidth: CGFloat = 0

    // MARK: - Currency Conversion

    private struct ConversionKey: Equatable {
        let amount: String
        let currency: String
    }

    @State private var convertedAmount: Double?

    // Shared formatters — created once, reused on every call
    private static let displayFormatter: NumberFormatter = {
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

    // Static UIFont for text-width measurement in updateFontSize.
    // Falls back to system bold if "Inter" PostScript name doesn't match.
    private static let measureFont: UIFont =
        UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)
    private static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Amount display — tap to focus, long-press for copy/paste
            Button {
                isFocused = true
            } label: {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: AppSpacing.xs) {
                        Text(displayAmount)
                            .font(.custom("Inter", size: currentFontSize).weight(.bold))
                            .contentTransition(.numericText())
                            .foregroundStyle(errorMessage != nil ? AppColors.destructive : AppColors.textPrimary)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayAmount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        if isFocused {
                            BlinkingCursor()
                        }
                    }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowConversion)

            // Hidden TextField captures keyboard input
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    updateDisplayAmount(newValue)
                    onAmountChange?(newValue)
                }
                // Debounced currency conversion — auto-cancels when amount or currency changes
                .task(id: ConversionKey(amount: amount, currency: selectedCurrency)) {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await updateConvertedAmount()
                }

            // Currency selector (centred)
            CurrencySelectorView(selectedCurrency: $selectedCurrency)

            // Validation error
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppSpacing.lg)
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
            updateDisplayAmount(amount)
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
            } else if let formatted = Self.displayFormatter.string(from: number) {
                newDisplayAmount = formatted
            } else {
                newDisplayAmount = formatLargeNumber(decimal)
            }
        } else {
            newDisplayAmount = cleaned
        }

        displayAmount = newDisplayAmount
    }

    private func formatLargeNumber(_ decimal: Decimal) -> String {
        if let formatted = Self.convertedAmountFormatter.string(from: NSDecimalNumber(decimal: decimal)) {
            return formatted
        }

        let string = String(describing: decimal)
        if string.contains(".") {
            let parts = string.components(separatedBy: ".")
            let intPart = groupDigitsInternal(parts[0])
            let fracPart = parts.count > 1 ? String(parts[1].prefix(2)) : ""
            return fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
        }
        return groupDigitsInternal(string)
    }

    private func groupDigitsInternal(_ integerString: String) -> String {
        var result = ""
        var count = 0
        for char in integerString.reversed() {
            if count > 0 && count % 3 == 0 { result = " " + result }
            result = String(char) + result
            count += 1
        }
        return result
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

        let textSize = (testText as NSString).size(withAttributes: Self.measureAttributes)
        let totalWidth = textSize.width

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
}

// BlinkingCursor is defined in Views/Components/AnimatedInputComponents.swift

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
