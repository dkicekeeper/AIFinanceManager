# План улучшения форм транзакций

**Дата создания:** 2026-01-19  
**Статус:** 🟡 В планировании  
**Приоритет:** Высокий

---

## 🎯 Цели

1. Унифицировать UI/UX всех форм транзакций
2. Улучшить ввод суммы (большие цифры в центре)
3. Улучшить выбор валюты (FilterChip вместо Picker)
4. Полная локализация всех форм
5. Соответствие дизайн-системе на 95%+

---

## 📋 План по фазам

### Phase 1: Создание компонентов (2-3 часа)

#### Задача 1.1: AmountInputView
**Файл:** `AIFinanceManager/Views/Components/AmountInputView.swift`

**Требования:**
- Большой центрированный текст (56-64pt)
- Форматирование с разделителями тысяч
- Поддержка ввода через скрытый TextField
- Отображение ошибок
- Анимация при фокусе

**API:**
```swift
struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    let onAmountChange: ((String) -> Void)?
    
    @FocusState private var isFocused: Bool
}
```

**Дизайн:**
```
┌─────────────────────────────┐
│                             │
│      1,234.56              │  ← 56pt, bold, rounded
│                             │
│  [₸] [₽] [€] [$] [£]      │  ← CurrencySelectorView
│                             │
│  Ошибка (если есть)        │  ← Красный текст
└─────────────────────────────┘
```

**Критерии приемки:**
- ✅ Текст суммы минимум 56pt
- ✅ Центрирован по горизонтали
- ✅ Форматирование работает корректно
- ✅ Валидация отображается
- ✅ Работает с клавиатурой .decimalPad

---

#### Задача 1.2: CurrencySelectorView
**Файл:** `AIFinanceManager/Views/Components/CurrencySelectorView.swift`

**Требования:**
- Горизонтальный ScrollView
- Использование FilterChip для каждой валюты
- Визуальная индикация выбранной валюты
- Haptic feedback при выборе

**API:**
```swift
struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let availableCurrencies: [String] = ["KZT", "USD", "EUR", "RUB", "GBP"]
}
```

**Дизайн:**
```
┌─────────────────────────────────────┐
│  [₸] [₽] [€] [$] [£]              │  ← FilterChip для каждой
│   ↑ selected (blue background)      │
└─────────────────────────────────────┘
```

**Критерии приемки:**
- ✅ Все валюты видны в горизонтальном ScrollView
- ✅ Выбранная валюта выделена (синий фон)
- ✅ Haptic feedback при выборе
- ✅ Использует FilterChip из дизайн-системы

---

### Phase 2: Локализация (1-2 часа)

#### Задача 2.1: Добавить ключи локализации

**Файлы:**
- `AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings`
- `AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings`

**Новые ключи:**

```strings
// MARK: - Transaction Forms
"transactionForm.amount" = "Amount" / "Сумма"
"transactionForm.description" = "Description" / "Описание"
"transactionForm.descriptionPlaceholder" = "Description (optional)" / "Описание (необязательно)"
"transactionForm.category" = "Category" / "Категория"
"transactionForm.selectCategory" = "Select category" / "Выберите категорию"
"transactionForm.noCategories" = "No available categories. Create categories first." / "Нет доступных категорий. Создайте категории сначала."
"transactionForm.transfer" = "Transfer" / "Перевод"
"transactionForm.topUp" = "Top Up" / "Пополнение"
"transactionForm.toAccount" = "To Account" / "Счет получателя"
"transactionForm.fromAccount" = "From Account" / "Счет источника"
"transactionForm.noAccountsForTransfer" = "No other accounts for transfer" / "Нет других счетов для перевода"
"transactionForm.enterPositiveAmount" = "Enter a positive amount" / "Введите положительную сумму"
"transactionForm.selectCategoryIncome" = "Select income category" / "Выберите категорию дохода"
"transactionForm.cannotTransferToSame" = "Cannot transfer to the same account" / "Нельзя перевести средства на тот же счет"
"transactionForm.accountNotFound" = "Account not found" / "Счет не найден"
"transactionForm.depositTopUp" = "Top Up Deposit" / "Пополнение депозита"
"transactionForm.depositWithdrawal" = "Withdraw from Deposit" / "Перевод с депозита"
"transactionForm.accountTopUp" = "Top Up Account" / "Пополнение счета"
"transactionForm.editTransaction" = "Edit Transaction" / "Редактировать операцию"
"transactionForm.recurring" = "Recurring" / "Повторяющаяся"
"transactionForm.makeRecurring" = "Make this recurring" / "Сделать повторяющейся"
"transactionForm.searchSubcategories" = "Search subcategories" / "Поиск подкатегорий"
"transactionForm.searchAndAddSubcategories" = "Search and add subcategories" / "Поиск и добавление подкатегорий"
```

**Критерии приемки:**
- ✅ Все ключи добавлены в EN и RU
- ✅ Нет дублирования существующих ключей
- ✅ Форматирование соответствует стандарту

---

### Phase 3: Рефакторинг VoiceInputConfirmationView (1 час)

#### Задача 3.1: Заменить ввод суммы
**Файл:** `AIFinanceManager/Views/VoiceInputConfirmationView.swift`

**Изменения:**
- Удалить `TextField` и `Picker` для валюты (строки 94-128)
- Добавить `AmountInputView`
- Обновить валидацию для работы с новым компонентом

**До:**
```swift
Section(header: Text(String(localized: "transaction.amount"))) {
    HStack(spacing: AppSpacing.md) {
        TextField("0.00", text: $amountText)
        Picker("", selection: $selectedCurrency) { ... }
    }
}
```

**После:**
```swift
Section(header: Text(String(localized: "transaction.amount"))) {
    AmountInputView(
        amount: $amountText,
        selectedCurrency: $selectedCurrency,
        errorMessage: amountWarning
    )
}
```

**Критерии приемки:**
- ✅ AmountInputView работает корректно
- ✅ Валидация работает
- ✅ Визуально улучшен ввод суммы

---

### Phase 4: Рефакторинг AccountActionView (1.5 часа)

#### Задача 4.1: Локализация
**Файл:** `AIFinanceManager/Views/AccountActionView.swift`

**Изменения:**
- Заменить все хардкод строки на `String(localized:)`
- Использовать ключи из Phase 2

**Список замен:**
- Строка 58: `"Перевод"` → `String(localized: "transactionForm.transfer")`
- Строка 59: `"Пополнение"` → `String(localized: "transactionForm.topUp")`
- Строка 68: `"Категория"` → `String(localized: "transactionForm.category")`
- И т.д. (см. анализ)

**Критерии приемки:**
- ✅ Нет хардкода строк
- ✅ Все строки локализованы

#### Задача 4.2: Заменить ввод суммы
**Аналогично Phase 3.1**

#### Задача 4.3: Применить AppTypography
- Заменить все `.font()` на `AppTypography.*`
- Унифицировать стили текста

**Критерии приемки:**
- ✅ Все тексты используют AppTypography
- ✅ Нет прямых вызовов `.font()`

---

### Phase 5: Рефакторинг EditTransactionView (1.5 часа)

#### Задача 5.1: Локализация
**Файл:** `AIFinanceManager/Views/EditTransactionView.swift`

**Изменения:**
- Заменить все хардкод строки (английские и русские)
- Использовать ключи из Phase 2

**Список замен:**
- Строка 77: `"Account"` → `String(localized: "transaction.account")`
- Строка 94: `"To Account"` → `String(localized: "transactionForm.toAccount")`
- Строка 129: `"Amount"` → `String(localized: "transactionForm.amount")`
- И т.д.

#### Задача 5.2: Добавить выбор валюты
**Текущее состояние:** Нет выбора валюты (используется валюта транзакции)

**Изменения:**
- Добавить `@State private var selectedCurrency: String`
- Инициализировать из `transaction.currency`
- Добавить `CurrencySelectorView` в секцию Amount
- Обновить логику сохранения для учета выбранной валюты

**Критерии приемки:**
- ✅ Можно выбрать валюту при редактировании
- ✅ Валюты конвертируются корректно

#### Задача 5.3: Заменить ввод суммы
**Аналогично Phase 3.1**

---

### Phase 6: Тестирование (1 час)

#### Задача 6.1: Функциональное тестирование
- ✅ Ввод суммы работает во всех формах
- ✅ Выбор валюты работает
- ✅ Валидация работает
- ✅ Сохранение транзакций работает

#### Задача 6.2: UI тестирование
- ✅ Проверка на iPhone SE (маленький экран)
- ✅ Проверка на iPhone 14 Pro Max (большой экран)
- ✅ Проверка в темной теме
- ✅ Проверка с Dynamic Type (большой текст)

#### Задача 6.3: Локализация тестирование
- ✅ Переключение EN/RU
- ✅ Все строки отображаются корректно
- ✅ Нет хардкода

#### Задача 6.4: Accessibility тестирование
- ✅ VoiceOver работает
- ✅ Все элементы доступны
- ✅ Правильные accessibility labels

---

## 📊 Оценка времени

| Фаза | Задачи | Время | Приоритет |
|------|--------|------|-----------|
| Phase 1 | Создание компонентов | 2-3 ч | P0 |
| Phase 2 | Локализация | 1-2 ч | P0 |
| Phase 3 | VoiceInputConfirmationView | 1 ч | P1 |
| Phase 4 | AccountActionView | 1.5 ч | P1 |
| Phase 5 | EditTransactionView | 1.5 ч | P1 |
| Phase 6 | Тестирование | 1 ч | P0 |
| **Итого** | | **8-10 ч** | |

---

## 🎨 Дизайн-макеты

### AmountInputView - Визуальный дизайн

**Состояние: Пусто**
```
┌─────────────────────────────┐
│         Сумма               │
│                             │
│         0.00                │  ← Серый, 56pt
│                             │
│  [₸] [₽] [€] [$] [£]      │
└─────────────────────────────┘
```

**Состояние: Ввод**
```
┌─────────────────────────────┐
│         Сумма               │
│                             │
│      1,234.56              │  ← Синий, 56pt, bold
│                             │
│  [₸] [₽] [€] [$] [£]      │
└─────────────────────────────┘
```

**Состояние: Ошибка**
```
┌─────────────────────────────┐
│         Сумма               │
│                             │
│      1,234.56              │  ← Красная рамка
│                             │
│  [₸] [₽] [€] [$] [£]      │
│                             │
│  Введите корректную сумму   │  ← Красный текст
└─────────────────────────────┘
```

### CurrencySelectorView - Визуальный дизайн

```
┌─────────────────────────────────────┐
│  [₸] [₽] [€] [$] [£]              │
│   ↑ selected                        │
│   (синий фон, белый текст)          │
└─────────────────────────────────────┘
```

---

## 🔧 Технические детали

### AmountInputView - Реализация

```swift
import SwiftUI

struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    var onAmountChange: ((String) -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    @State private var displayAmount: String = "0.00"
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Большой отображаемый текст
            Text(displayAmount)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(borderColor, lineWidth: isFocused ? 2 : (errorMessage != nil ? 1 : 0))
                )
                .padding(.vertical, AppSpacing.lg)
            
            // Скрытый TextField для ввода
            TextField("", text: $amount)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: amount) { _, newValue in
                    updateDisplayAmount(newValue)
                    onAmountChange?(newValue)
                }
            
            // Выбор валюты
            CurrencySelectorView(selectedCurrency: $selectedCurrency)
            
            // Ошибка
            if let error = errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.lg)
        .onAppear {
            updateDisplayAmount(amount)
        }
    }
    
    private var foregroundColor: Color {
        if errorMessage != nil {
            return .red
        } else if isFocused {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var borderColor: Color {
        if errorMessage != nil {
            return .red
        } else if isFocused {
            return .blue
        } else {
            return .clear
        }
    }
    
    private func updateDisplayAmount(_ text: String) {
        // Очищаем от валютных символов
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if cleaned.isEmpty {
            displayAmount = "0.00"
            return
        }
        
        // Парсим число
        if let number = Double(cleaned) {
            if let formatted = formatter.string(from: NSNumber(value: number)) {
                displayAmount = formatted
            } else {
                displayAmount = String(format: "%.2f", number)
            }
        } else {
            displayAmount = cleaned
        }
    }
}
```

### CurrencySelectorView - Реализация

```swift
import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let availableCurrencies: [String]
    
    init(
        selectedCurrency: Binding<String>,
        availableCurrencies: [String] = ["KZT", "USD", "EUR", "RUB", "GBP"]
    ) {
        self._selectedCurrency = selectedCurrency
        self.availableCurrencies = availableCurrencies
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(availableCurrencies, id: \.self) { currency in
                    FilterChip(
                        title: Formatting.currencySymbol(for: currency),
                        isSelected: selectedCurrency == currency,
                        onTap: {
                            selectedCurrency = currency
                            HapticManager.selection()
                        }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}
```

---

## ✅ Чеклист выполнения

### Phase 1: Компоненты
- [ ] Создан AmountInputView
- [ ] Создан CurrencySelectorView
- [ ] Компоненты протестированы
- [ ] Добавлены Preview

### Phase 2: Локализация
- [ ] Добавлены все ключи в EN
- [ ] Добавлены все ключи в RU
- [ ] Проверено отсутствие дубликатов

### Phase 3: VoiceInputConfirmationView
- [ ] Заменен ввод суммы
- [ ] Заменен выбор валюты
- [ ] Валидация работает
- [ ] Тестирование пройдено

### Phase 4: AccountActionView
- [ ] Все строки локализованы
- [ ] Заменен ввод суммы
- [ ] Заменен выбор валюты
- [ ] Применен AppTypography
- [ ] Тестирование пройдено

### Phase 5: EditTransactionView
- [ ] Все строки локализованы
- [ ] Добавлен выбор валюты
- [ ] Заменен ввод суммы
- [ ] Применен AppTypography
- [ ] Тестирование пройдено

### Phase 6: Тестирование
- [ ] Функциональное тестирование
- [ ] UI тестирование
- [ ] Локализация тестирование
- [ ] Accessibility тестирование

---

## 🚨 Риски и митигация

### Риск 1: Производительность AmountInputView
**Проблема:** Большой текст может влиять на производительность  
**Митигация:** Использовать `.drawingGroup()` для оптимизации рендеринга

### Риск 2: Клавиатура перекрывает сумму
**Проблема:** На маленьких экранах клавиатура может перекрыть большой текст  
**Митигация:** Использовать `ScrollViewReader` для автоматической прокрутки

### Риск 3: Форматирование может конфликтовать с вводом
**Проблема:** Автоформатирование может мешать вводу  
**Митигация:** Форматировать только при потере фокуса или с задержкой

---

## 📝 Примечания

- Все изменения должны быть обратно совместимы
- Не ломать существующий функционал
- Сохранить все валидации
- Сохранить все бизнес-логики

---

**Следующий шаг:** Начать с Phase 1 - создание компонентов
