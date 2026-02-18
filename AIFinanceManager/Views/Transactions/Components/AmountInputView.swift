//
//  AmountInputView.swift
//  AIFinanceManager
//
//  Large centered amount input with currency selector
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
    @State private var previousRawAmount: String = "" // Исходное число без форматирования
    @State private var animatedCharacters: [AnimatedChar] = []
    @State private var currentFontSize: CGFloat = 56
    @State private var containerWidth: CGFloat = 0

    // MARK: - Currency Conversion
    @State private var convertedAmount: Double?
    @State private var conversionTask: Task<Void, Never>?
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.decimalSeparator = "."
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Большой отображаемый текст с курсором
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
            .onTapGesture {
                isFocused = true
            }

            // Конвертированная сумма
            convertedAmountView

            // Скрытый TextField для ввода
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

            // Выбор валюты (центрированный)
            CurrencySelectorView(selectedCurrency: $selectedCurrency)
                .onChange(of: selectedCurrency) { _, _ in
                    Task {
                        await updateConvertedAmount()
                    }
                }

            // Ошибка (по центру)
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
//                    .frame(maxWidth: .infinity)
//                    .padding(.top, AppSpacing.xs)
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
            // Обновляем размер при изменении текста
            if containerWidth > 0 {
                updateFontSize(for: containerWidth)
            }
        }
        .onAppear {
            updateDisplayAmount(amount)
            previousAmount = displayAmount
            let cleaned = amount
                .replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "₸", with: "")
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "₽", with: "")
                .replacingOccurrences(of: "£", with: "")
                .trimmingCharacters(in: .whitespaces)
            previousRawAmount = cleaned.isEmpty ? "0" : cleaned
            animatedCharacters = Array(displayAmount).enumerated().map { index, char in
                AnimatedChar(id: UUID(), character: char, isNew: false)
            }

            // Автоматически активируем фокус при появлении
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                Text(String(localized: "currency.conversion.approximate"))
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
                    // Loader placeholder
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
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .replacingOccurrences(of: "£", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private func formatConvertedAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0

        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    private func updateConvertedAmountDebounced() {
        conversionTask?.cancel()

        conversionTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await updateConvertedAmount()
        }
    }

    private func updateConvertedAmount() async {
        guard selectedCurrency != baseCurrency else {
            await MainActor.run {
                convertedAmount = nil
            }
            return
        }

        guard let numericAmount = parseAmount(amount), numericAmount > 0 else {
            await MainActor.run {
                convertedAmount = nil
            }
            return
        }

        // Попытка синхронной конвертации через кэш
        if let syncConverted = CurrencyConverter.convertSync(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            await MainActor.run {
                convertedAmount = syncConverted
            }
            return
        }

        // Асинхронная загрузка курса
        if let asyncConverted = await CurrencyConverter.convert(
            amount: numericAmount,
            from: selectedCurrency,
            to: baseCurrency
        ) {
            await MainActor.run {
                convertedAmount = asyncConverted
            }
        }
    }
    
    
    private func updateDisplayAmount(_ text: String) {
        // Очищаем от валютных символов и пробелов
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .replacingOccurrences(of: "£", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        var newDisplayAmount: String
        
        if cleaned.isEmpty {
            newDisplayAmount = "0"
        } else if let decimal = Decimal(string: cleaned) {
            // Используем Decimal для точной работы с большими числами
            let number = NSDecimalNumber(decimal: decimal)
            if number.compare(NSDecimalNumber.zero) == .orderedSame {
                newDisplayAmount = "0"
            } else {
                // Всегда используем группировку
                if let formatted = formatter.string(from: number) {
                    newDisplayAmount = formatted
                } else {
                    // Fallback: форматируем вручную для очень больших чисел
                    newDisplayAmount = formatLargeNumber(decimal)
                }
            }
        } else {
            newDisplayAmount = cleaned
        }
        
        // Обновляем анимированные символы
        // Сравниваем исходное число без форматирования, чтобы избежать ложных срабатываний из-за пробелов
        updateAnimatedCharacters(newAmount: newDisplayAmount, rawAmount: cleaned)
        displayAmount = newDisplayAmount
    }
    
    private func formatLargeNumber(_ decimal: Decimal) -> String {
        // Форматируем большие числа вручную с пробелами
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        
        if let formatted = formatter.string(from: NSDecimalNumber(decimal: decimal)) {
            return formatted
        }
        
        // Если и это не сработало, форматируем как строку
        let string = String(describing: decimal)
        if string.contains(".") {
            let parts = string.components(separatedBy: ".")
            let integerPart = parts[0]
            let decimalPart = parts.count > 1 ? parts[1].prefix(2) : ""
            
            // Добавляем пробелы каждые 3 цифры
            var formattedInteger = ""
            var count = 0
            for char in integerPart.reversed() {
                if count > 0 && count % 3 == 0 {
                    formattedInteger = " " + formattedInteger
                }
                formattedInteger = String(char) + formattedInteger
                count += 1
            }
            
            return decimalPart.isEmpty ? formattedInteger : "\(formattedInteger).\(decimalPart)"
        } else {
            // Только целая часть
            var formatted = ""
            var count = 0
            for char in string.reversed() {
                if count > 0 && count % 3 == 0 {
                    formatted = " " + formatted
                }
                formatted = String(char) + formatted
                count += 1
            }
            return formatted
        }
    }
    
    private func spacingForFontSize(_ size: CGFloat) -> CGFloat {
        // Пропорциональный spacing: при размере 56 = 2, при размере 20 = 0.5
        return max(0.5, (size / 56) * 2)
    }
    
    private func updateFontSize(for width: CGFloat) {
        // Для "0" всегда используем базовый размер
        if displayAmount == "0" {
            currentFontSize = 56
            return
        }
        
        guard width > 0 else { return } // Не обновляем если ширина еще не известна
        
        let testText = displayAmount.isEmpty ? "0" : displayAmount
        // Учитываем padding контейнера (AppSpacing.lg * 2) и место для курсора (~20)
        let maxWidth = width - (AppSpacing.lg * 2) - 20
        let baseSize: CGFloat = 56
        
        // Учитываем spacing между символами при базовом размере
        let charCount = testText.count
        let baseSpacing = spacingForFontSize(baseSize)
        let totalSpacing = CGFloat(max(0, charCount - 1)) * baseSpacing
        
        let testFont = UIFont.systemFont(ofSize: baseSize, weight: .bold)
        let attributes = [NSAttributedString.Key.font: testFont]
        let textSize = (testText as NSString).size(withAttributes: attributes)
        let totalWidth = textSize.width + totalSpacing
        
        let newFontSize: CGFloat
        if totalWidth > maxWidth && maxWidth > 0 {
            // Уменьшаем размер только если не помещается
            let scaleFactor = maxWidth / totalWidth
            newFontSize = max(24, min(baseSize, baseSize * scaleFactor))
        } else {
            // Если помещается, используем базовый размер
            newFontSize = baseSize
        }
        
        // Обновляем только если размер действительно изменился (избегаем лишних обновлений)
        if abs(currentFontSize - newFontSize) > 0.5 {
            currentFontSize = newFontSize
        }
    }
    
    private func updateAnimatedCharacters(newAmount: String, rawAmount: String) {
        // Сравниваем исходные числа без форматирования
        let newRawChars = Array(rawAmount)
        let previousRawChars = Array(previousRawAmount)
        
        // Определяем, какие позиции в raw строке изменились
        var changedRawPositions: Set<Int> = []
        
        // Сравниваем по позициям
        let maxLength = max(newRawChars.count, previousRawChars.count)
        for i in 0..<maxLength {
            if i >= newRawChars.count {
                // Символ удален
                continue
            } else if i >= previousRawChars.count {
                // Новый символ
                changedRawPositions.insert(i)
            } else if newRawChars[i] != previousRawChars[i] {
                // Символ изменился
                changedRawPositions.insert(i)
            }
        }
        
        // Теперь проходим по форматированной строке и определяем, какие символы анимировать
        let formattedChars = Array(newAmount)
        var updated: [AnimatedChar] = []
        var rawIndex = 0 // Индекс в raw строке (без пробелов)
        
        for (formattedIndex, formattedChar) in formattedChars.enumerated() {
            var isNew = false
            var charId: UUID
            
            if formattedChar == " " {
                // Пробел - не анимируем
                if formattedIndex < animatedCharacters.count {
                    charId = animatedCharacters[formattedIndex].id
                } else {
                    charId = UUID()
                }
                updated.append(AnimatedChar(id: charId, character: formattedChar, isNew: false))
                continue
            }
            
            // Это цифра или точка - проверяем, изменилась ли она
            if rawIndex < newRawChars.count {
                if changedRawPositions.contains(rawIndex) {
                    // Эта позиция изменилась
                    isNew = true
                    charId = UUID()
                } else {
                    // Позиция не изменилась
                    isNew = false
                    // Пытаемся найти соответствующий символ в предыдущей анимированной строке
                    if formattedIndex < animatedCharacters.count && animatedCharacters[formattedIndex].character == formattedChar {
                        charId = animatedCharacters[formattedIndex].id
                    } else {
                        charId = UUID()
                    }
                }
                rawIndex += 1
            } else {
                // Неожиданная ситуация
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
