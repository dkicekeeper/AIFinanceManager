# COMPONENT_INVENTORY.md
## AIFinanceManager — Полный реестр UI-компонентов

> **Дата:** 2026-01-28 | **Метод:**静态ный анализ кода (grep + read всех .swift файлов)

---

## Структура документа
1. [Компоненты по категориям](#компоненты-по-категориям) — таблица каждого компонента
2. [Инлайн-View-struct в файлах экранов](#инлайн-view-struct) — встроенные компоненты, не вынесенные в отдельные файлы
3. [Дубли UI](#дубли-ui) — одинаковые UI-блоки в разных вью
4. [Нарушения SRP / «умные» компоненты](#нарушения-srp) — компоненты с зависимостями на ViewModel и бизнес-логикой

---

## 1. Компоненты по категориям

### 1.1 Cards (карточки)

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `AccountCard` | `Views/Components/AccountCard.swift` | Карточка счёта в горизонтальном carousel — логотип банка + имя + баланс | `account: Account`, `onTap: () -> Void` | `onTap` | `ContentView` (строка 458) |
| `AnalyticsCard` | `Views/Components/AnalyticsCard.swift` | Сводочная карточка income/expense с progress bar — отображает `Summary` | `summary: Summary`, `currency: String` | — | `ContentView` (строка 515) |
| `SubscriptionCard` | `Views/Components/SubscriptionCard.swift` | Карточка подписки в grid — логотип бренда + сумма + статус + next charge | `subscription: RecurringSeries` | — | `SubscriptionsListView` (строки 118, 221) |
| `SubscriptionsCardView` | `Views/SubscriptionsCardView.swift` | Сводочная карточка подписок на home — сумма + иконки подписок | (зависимости ниже) | — | `ContentView` через `subscriptionsNavigationLink` |

### 1.2 Rows (строки списков)

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `AccountRow` | `Views/Components/AccountRow.swift` | Строка счёта в management list — логотип + имя + баланс + deposit info + swipe delete | `account: Account`, `currency: String`, `onEdit: () -> Void`, `onDelete: () -> Void` | `onEdit`, `onDelete` | `AccountsManagementView` (строки 39, 433) |
| `CategoryRow` | `Views/Components/CategoryRow.swift` | Строка категории — иконка + имя + budget progress ring + swipe edit/delete | `category: CustomCategory`, `isDefault: Bool`, `budgetProgress: BudgetProgress?`, `onEdit: () -> Void`, `onDelete: () -> Void` | `onEdit`, `onDelete` | `CategoriesManagementView` (строки 42, 420) |
| `SubcategoryRow` | `Views/Components/SubcategoryRow.swift` | Строка подкатегории в selector — имя + checkmark | `subcategory: Subcategory`, `@Binding isSelected: Bool`, `onToggle: () -> Void` | `onToggle` | (только через `SubcategorySelectorView` внутренний loop) |
| `DepositTransactionRow` | `Views/Components/DepositTransactionRow.swift` | Строка транзакции в deposit detail — type-icon + дата + сумма с цветом | `transaction: Transaction`, `currency: String`, `depositAccountId: String` | — | `DepositDetailView` |
| `BankLogoRow` | `Views/Components/BankLogoRow.swift` | Строка банковского логотипа в picker — логотип + имя + selection indicator | `bank: BankLogo`, `isSelected: Bool`, `onSelect: () -> Void` | `onSelect` | `AccountsManagementView` (строки 305, 318, 330) |
| `InfoRow` | `Views/Components/InfoRow.swift` | Строка label + value — двухколоночный row для detail screens | `label: String`, `value: String` | — | `DepositDetailView` (строки 236, 240, 244, 250), `SubscriptionDetailView` (строки 240, 241, 244, 249, 252) |
| `TransactionCard` | `Views/Components/TransactionCard.swift` | Основная строка транзакции в history — иконка + описание + сумма + account info + swipe edit/stop recurring | `transaction: Transaction`, `currency: String`, `customCategories: [CustomCategory]`, `accounts: [Account]`, `viewModel: TransactionsViewModel?`, `categoriesViewModel: CategoriesViewModel?` | — (edit modal + stop recurring via internal state) | `HistoryTransactionsList` (строка 90) |

### 1.3 Buttons / Controls

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `CategoryChip` | `Views/Components/CategoryChip.swift` | Монетка категории с иконкой + optional budget ring | `category: String`, `type: TransactionType`, `customCategories: [CustomCategory]`, `isSelected: Bool`, `onTap: () -> Void`, `budgetProgress: BudgetProgress?`, `budgetAmount: Double?` | `onTap` | `QuickAddTransactionView` (строка 72), `CategorySelectorView` (строка 59) |
| `FilterChip` | `Views/Components/FilterChip.swift` | Pill-shaped фильтр — title + optional icon + selected state | `title: String`, `icon: String?`, `isSelected: Bool`, `onTap: () -> Void` | `onTap` | `HistoryFilterSection` (строка 22), `SubcategorySelectorView` (строка 39) |
| `AccountRadioButton` | `Views/Components/AccountRadioButton.swift` | Radio-кнопка счёта — карточка + border при выборе | `account: Account`, `isSelected: Bool`, `onTap: () -> Void` | `onTap` | `AccountSelectorView` (строка 45), `DepositTransferView` (строка 46) |
| `CategoryFilterButton` | `Views/Components/CategoryFilterButton.swift` | Кнопка-фильтр категории в history toolbar — адаптивная иконка/текст по текущему фильтру | `transactionsViewModel: TransactionsViewModel`, `categoriesViewModel: CategoriesViewModel`, `onTap: () -> Void` | `onTap` | `HistoryFilterSection` (строка 35) |
| `RecurringToggleView` | `Views/Components/RecurringToggleView.swift` | Toggle повторяющейся транзакции + frequency picker | `@Binding isRecurring: Bool`, `@Binding selectedFrequency: RecurringFrequency` | (bindings) | `QuickAddTransactionView` (строка 314), `EditTransactionView` (строка 138) |
| `DateSectionHeader` | `Views/Components/DateSectionHeader.swift` | Заголовок группы по дате + сумма расходов за день | `dateKey: String`, `dayExpenses: Double`, `currency: String` | — | `HistoryTransactionsList` (строка 145) |

### 1.4 Inputs (поля ввода / selectors)

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `AmountInputView` | `Views/Components/AmountInputView.swift` | Поле суммы с анимированными цифрами + currency selector | `@Binding amount: String`, `@Binding selectedCurrency: String`, `errorMessage: String?`, `onAmountChange: ((String) -> Void)?` | `onAmountChange` | `QuickAddTransactionView` (строка 281), `EditTransactionView` (строка 84), `AccountActionView` (строка 67), `VoiceInputConfirmationView` (строка 90) |
| `DateButtonsView` | `Views/Components/DateButtonsView.swift` | Кнопки today/yesterday + full date picker | `@Binding selectedDate: Date`, `isDisabled: Bool`, `onSave: (Date) -> Void` | `onSave` | (встроен в edit forms через DatePicker) |
| `DescriptionTextField` | `Views/Components/DescriptionTextField.swift` | Многострочное поле описания с лимитом строк | `@Binding text: String`, `placeholder: String`, `minLines: Int`, `maxLines: Int` | — | `AccountActionView` (строка 101), `VoiceInputConfirmationView` (строка 158), `QuickAddTransactionView` (строка 322), `EditTransactionView` (строка 144) |
| `AccountSelectorView` | `Views/Components/AccountSelectorView.swift` | Modal выбора счёта — список radio buttons + empty/warning states | `accounts: [Account]`, `@Binding selectedAccountId: String?`, `onSelectionChange: ((String?) -> Void)?`, `emptyStateMessage: String?`, `warningMessage: String?` | `onSelectionChange` | `EditTransactionView` (строки 93, 98, 104), `AccountActionView` (строка 78), `QuickAddTransactionView` (строка 293), `VoiceInputConfirmationView` (строка 116) |
| `CategorySelectorView` | `Views/Components/CategorySelectorView.swift` | Modal выбора категории — grid chips + empty/warning + budget map | `categories: [String]`, `type: TransactionType`, `customCategories: [CustomCategory]`, `@Binding selectedCategory: String?`, `onSelectionChange: ((String?) -> Void)?`, `emptyStateMessage: String?`, `warningMessage: String?`, `budgetProgressMap: [String: BudgetProgress]?`, `budgetAmountMap: [String: Double]?` | `onSelectionChange` | `EditTransactionView` (строка 113), `AccountActionView` (строка 87), `VoiceInputConfirmationView` (строка 127) |
| `SubcategorySelectorView` | `Views/Components/SubcategorySelectorView.swift` | Modal выбора подкатегорий — list + search link | `categoriesViewModel: CategoriesViewModel`, `categoryId: String?`, `@Binding selectedSubcategoryIds: Set<String>`, `onSearchTap: () -> Void` | `onSearchTap` | `EditTransactionView` (строка 126), `QuickAddTransactionView` (строка 303), `VoiceInputConfirmationView` (строка 142) |
| `CurrencySelectorView` | `Views/Components/CurrencySelectorView.swift` | Menu выбора валюты | `@Binding selectedCurrency: String`, `availableCurrencies: [String]` | (binding) | `AmountInputView` (строка 75) |
| `SegmentedPickerView<T>` | `Views/Components/SegmentedPickerView.swift` | Generic обёртка для Picker с segmented style | `title: String`, `@Binding selection: T`, `options: [(label: String, value: T)]` | (binding) | `AccountActionView` (строка 56), `VoiceInputConfirmationView` (строка 80) |
| `IconPickerView` | `Views/Components/IconPickerView.swift` | Grid выбора SF Symbol иконки | `@Binding selectedIconName: String` | (binding + dismiss) | `SubscriptionEditView` (строка 245), `CategoriesManagementView` (строка 338) |

### 1.5 Filters

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `HistoryFilterSection` | `Views/Components/HistoryFilterSection.swift` | Контейнер фильтров history — account menu + category button + text search | `transactionsViewModel`, `accountsViewModel`, `categoriesViewModel`, `timeFilterManager`, `@Binding selectedAccountFilter: String?`, `@Binding showingCategoryFilter: Bool` | (bindings) | `HistoryView` (строка 72) |
| `AccountFilterMenu` | `Views/Components/AccountFilterMenu.swift` | Menu фильтрации по счёту | `accounts: [Account]`, `@Binding selectedAccountId: String?` | (binding) | `HistoryFilterSection` (строка 29) |
| `CategoryFilterView` | `Views/Components/CategoryFilterView.swift` | Modal multi-select фильтрации по категориям | `viewModel: TransactionsViewModel` | (dismiss + filter state) | `HistoryView` (строка 128) |

### 1.6 Empty / Error / Loading states

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `WarningMessageView` | `Views/Components/WarningMessageView.swift` | Баннер предупреждения/ошибки — иконка + текст | `message: String`, `color: Color` | — | `AccountSelectorView` (строка 62), `CategorySelectorView` (строка 82) |
| `SkeletonView` | `Views/Components/SkeletonView.swift` | Loading placeholder анимация | (нет — все параметры закомментированы) | — | (не используется снаружи, только внутренние скелетоны) |

### 1.7 Containers / Layouts

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `ExpenseIncomeProgressBar` | `Views/Components/ExpenseIncomeProgressBar.swift` | Двойной progress bar income/expense | `expenseAmount: Double`, `incomeAmount: Double`, `currency: String` | — | `AnalyticsCard` (строка 25) |

### 1.8 Specialized / Helpers

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `SiriWaveView` | `Views/Components/SiriWaveView.swift` | Анимация волны для voice recording | `amplitude: Double`, `frequency: Double`, `color: Color`, `animationSpeed: Double` | — | `VoiceInputView` |
| `HighlightedText` | `Views/Components/HighlightedText.swift` | Текст с подсвеченными entity (NLP output) | `text: String`, `entities: [RecognizedEntity]`, `font: Font` | — | `VoiceInputView` (строка 40) |
| `BrandLogoView` | `Views/Components/BrandLogoView.swift` | Логотип бренда через logo.dev API + async cache | `brandName: String?`, `size: CGFloat` | — | `SubscriptionCard` (строка 32), `SubscriptionCalendarView` (строка 172), `StaticSubscriptionIconsView` (строка 75), `SubscriptionDetailView` (строка 213) |
| `StaticSubscriptionIconsView` | `Views/Components/StaticSubscriptionIconsView.swift` | Overlapping иконки подписок (как stack аватаров) | `subscriptions: [RecurringSeries]` | — | `SubscriptionsCardView` (строка 61) |
| `SubscriptionCalendarView` | `Views/Components/SubscriptionCalendarView.swift` | Calendar grid с подписками по дням месяца | `subscriptions: [RecurringSeries]` | — | `SubscriptionsListView` (строка 21) |

### 1.9 Deposit-specific components

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `DepositRateChangeView` | `Views/Components/DepositRateChangeView.swift` | Форма изменения ставки депозита | `depositsViewModel: DepositsViewModel`, `account: Account`, `onComplete: () -> Void` | `onComplete` | `DepositDetailView` (строка 155) |
| `DepositTransferView` | `Views/Components/DepositTransferView.swift` | Форма перевода на/с депозита — account radio + amount + date | `transactionsViewModel: TransactionsViewModel`, `accountsViewModel: AccountsViewModel`, `depositAccount: Account`, `transferDirection: DepositTransferDirection`, `onComplete: () -> Void` | `onComplete` | `DepositDetailView` |

### 1.10 Sub-components (private structs inside files)

| Component | Parent File | Responsibility |
|-----------|-------------|----------------|
| `TransactionIconView` | `TransactionCardComponents.swift` | Иконка/цвет транзакции по типу + категории |
| `TransactionInfoView` | `TransactionCardComponents.swift` | Описание + account info (transfer vs regular) |
| `TransferAccountInfo` | `TransactionCardComponents.swift` | Отображение from/to для переводов |
| `RegularAccountInfo` | `TransactionCardComponents.swift` | Отображение account для обычных транзакций |
| `AnimatedDigit` / `BlinkingCursor` | `AmountInputView.swift` | Анимация цифр + мигающий курсор |
| `DateButtonsContent` / `DateButtonsDatePickerSheet` | `DateButtonsView.swift` | Внутренние layout-обёртки |
| `SiriWaveRecordingView` | `SiriWaveView.swift` | Multi-wave composition |
| `SubscriptionIconView` | `StaticSubscriptionIconsView.swift` | Единичная иконка в overlap stack |
| `AccountCardSkeleton` / `AnalyticsCardSkeleton` / `MainScreenLoadingView` | `SkeletonView.swift` | Loading placeholders |

---

## 2. Инлайн-View-struct (встроенные в файлы экранов, НЕ в компонентах)

Эти struct определены внутри файлов main screens, а не в `Views/Components/`. Некоторые используются в нескольких местах или могут быть выделены в отдельные файлы.

| Struct | Defined in | Line | Parameters | Used in | Рекомендация |
|--------|-----------|------|------------|---------|--------------|
| `RecognizedTextView` | `ContentView.swift` | 599 | `recognizedText: String`, `structuredRows: [[String]]?`, `viewModel: TransactionsViewModel`, `onImport: (CSVFile) -> Void`, `onCancel: () -> Void` | `ContentView` (строка 195) | **Выделить в Views/** — больше 120 строк, self-contained |
| `ErrorMessageView` | `ContentView.swift` | 723 | `message: String` | `ContentView` (строка 59) | **Выделить в Components/** — reusable error banner |
| `AccountEditView` | `AccountsManagementView.swift` | 176 | `accountsViewModel: AccountsViewModel`, `transactionsViewModel: TransactionsViewModel`, `account: Account?`, `onSave: (Account) -> Void`, `onCancel: () -> Void` | `ContentView` (строка 258), `AccountsManagementView` (строки 92, 155) | **Выделить в Views/** — используется из 2 разных файлов |
| `BankLogoPickerView` | `AccountsManagementView.swift` | 287 | `@Binding selectedLogo: BankLogo` | `AccountsManagementView` (строка 281), `DepositEditView` (строка 163) | **Выделить в Components/** — используется из 2 разных файлов |
| `CategoryEditView` | `CategoriesManagementView.swift` | 139 | `categoriesViewModel`, `transactionsViewModel`, `category: CustomCategory?`, `type: TransactionType`, `onSave: (CustomCategory) -> Void`, `onCancel: () -> Void` | `QuickAddTransactionView` (строка 126), `CategoriesManagementView` (строки 82, 97) | **Выделить в Views/** — используется из 2 разных файлов |
| `SubcategoryManagementRow` | `SubcategoriesManagementView.swift` | 82 | `subcategory: Subcategory`, `onEdit: () -> Void`, `onDelete: () -> Void` | `SubcategoriesManagementView` | Может остаться, но структура аналогична `AccountRow` / `CategoryRow` |
| `SubcategoryEditView` | `SubcategoriesManagementView.swift` | 106 | `categoriesViewModel: CategoriesViewModel`, `subcategory: Subcategory?`, `onSave: (Subcategory) -> Void`, `onCancel: () -> Void` | `SubcategoriesManagementView` (строки 56, 68) | Используется только в одном файле, но паттерн edit-view — выделить для консистентности |
| `AddTransactionModal` | `QuickAddTransactionView.swift` | ~111 | `category: String`, `type: TransactionType`, `currency: String`, `accounts: [Account]`, 3 ObservedObjects, `onDismiss: () -> Void` | `QuickAddTransactionView` (строка 111) | Большой (>200 строк), содержит бизнес-логику |
| `TransactionRow` | `SubscriptionDetailView.swift` | 321 | `transaction: Transaction`, `viewModel: TransactionsViewModel`, `isPlanned: Bool` | `SubscriptionDetailView` | **Дубль** — аналогична `DepositTransactionRow` по задаче |
| `AccountMappingDetailView` | `CSVEntityMappingView.swift` | 245 | `csvValue: String`, `accounts: [Account]`, `@Binding selectedAccountId: String?`, `onCreateNew: () -> Void` | `CSVEntityMappingView` | CSV-specific, может остаться |
| `CategoryMappingDetailView` | `CSVEntityMappingView.swift` | 284 | `csvValue: String`, `categories: [CustomCategory]`, `categoryType: TransactionType`, `@Binding selectedCategoryName: String?`, `onCreateNew: () -> Void` | `CSVEntityMappingView` | CSV-specific, может остаться |
| `LogoSearchResultRow` | `LogoSearchView.swift` | 235 | `result: LogoSearchResult`, `isSelected: Bool`, `onSelect: () -> Void` | `LogoSearchView` | Feature-specific, может остаться |
| `TransactionPreviewRow` | `TransactionPreviewView.swift` | 162 | `transaction: Transaction`, `isSelected: Bool`, `selectedAccountId: String?`, `availableAccounts: [Account]`, `onToggle: () -> Void`, `onAccountSelect: (String) -> Void` | `TransactionPreviewView` | Feature-specific, может остаться |
| `StatRow` | `CSVImportResultView.swift` | — | `label: String`, `value: String`, `color: Color`, `icon: String?` | `CSVImportResultView` | Аналогичен `InfoRow` — может использовать InfoRow |
| `DatePickerSheet` | `QuickAddTransactionView.swift` | — | `@Binding selectedDate: Date`, `onDateSelected: (Date) -> Void` | `QuickAddTransactionView` | Дубль date picker sheet |
| `RecordingIndicatorView` | `VoiceInputView.swift` | 223 | (none — internal animation state) | `VoiceInputView` | Feature-specific, может остаться |

---

## 3. Дубли UI

### 3.1 Edit Form Shell (NavigationView + Form + toolbar Save/Cancel)

Пять edit-view имеют **идентичную оболочку:**

| View | File | Toolbar pattern |
|------|------|-----------------|
| `AccountEditView` | `AccountsManagementView.swift:176` | NavView → Form → toolbar { xmark (leading), checkmark (trailing) } |
| `CategoryEditView` | `CategoriesManagementView.swift:139` | NavView → Form → toolbar { xmark (leading), checkmark (trailing) } |
| `SubcategoryEditView` | `SubcategoriesManagementView.swift:106` | NavView → Form → toolbar { xmark (leading), checkmark (trailing) } |
| `DepositEditView` | `DepositEditView.swift:10` | NavView → Form → toolbar { xmark (leading), checkmark (trailing) } |
| `SubscriptionEditView` | `SubscriptionEditView.swift:10` | NavView → Form → toolbar { xmark (leading), checkmark (trailing) } |

**Общий паттерн:**
```swift
NavigationView {
    Form { ... sections ... }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: onCancel) { Image(systemName: "xmark") }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { onSave(...) } label: { Image(systemName: "checkmark") }
            .disabled(validationFails)
        }
    }
    .onAppear { /* populate from entity */ }
}
```

**Рекомендация:** Выделить `EditSheetContainer<Content: View>` — wrapper с title, disabled state, onSave, onCancel.

---

### 3.2 Management List Shell (EmptyState + List + toolbar +)

| View | File | Pattern |
|------|------|---------|
| `AccountsManagementView` | `AccountsManagementView.swift:10` | Empty → EmptyStateView | List → ForEach → Row(onEdit/onDelete) |
| `CategoriesManagementView` | `CategoriesManagementView.swift:10` | Empty → EmptyStateView | List → ForEach → Row(onEdit/onDelete) |
| `SubcategoriesManagementView` | `SubcategoriesManagementView.swift:10` | Empty → EmptyStateView | List → ForEach → Row(onEdit/onDelete) |

**Общий паттерн:**
```swift
Group {
    if items.isEmpty {
        EmptyStateView(icon:, title:, description:, actionTitle:, action:)
    } else {
        List {
            ForEach(items) { item in
                Row(item: item, onEdit: { editing = item }, onDelete: { ... })
            }
        }
    }
}
.toolbar { ToolbarItem(.topBarTrailing) { Button("+") { showing = true } } }
.sheet(isPresented: $showingAdd) { EditView(entity: nil, onSave:, onCancel:) }
.sheet(item: $editing) { EditView(entity: $0, onSave:, onCancel:) }
```

---

### 3.3 Management Rows (tap-to-edit + swipe-to-delete)

| Component | File | Layout |
|-----------|------|--------|
| `AccountRow` | `AccountRow.swift` | HStack { logo + VStack(name, balance) + Spacer } + onTapGesture(onEdit) + swipeActions(delete) |
| `CategoryRow` | `CategoryRow.swift` | HStack { icon-circle + VStack(name, budget) + Spacer } + onTapGesture(onEdit) + swipeActions(delete) |
| `SubcategoryManagementRow` | `SubcategoriesManagementView.swift:82` | HStack { VStack(name) + Spacer } + onTapGesture(onEdit) + swipeActions(delete) |

**Рекомендация:** Generic `ManagementRow` с `leading: AnyView`, `trailing: AnyView?`, `onEdit`, `onDelete`.

---

### 3.4 Transaction Row Variants (date + amount + icon)

Три компонента отображают транзакции в list, но у каждого разный набор полей:

| Component | File | Показывает | Swipe actions |
|-----------|------|------------|---------------|
| `TransactionCard` | `TransactionCard.swift` | icon + description + category + account + amount + recurring badge | edit modal, stop recurring |
| `DepositTransactionRow` | `DepositTransactionRow.swift` | small icon + description + date + amount | нет |
| `TransactionRow` (inline) | `SubscriptionDetailView.swift:321` | clock? + date + amount + planned highlight | нет |

**DepositTransactionRow** и **TransactionRow** — функционально пересекаются: оба показывают дату + сумму + тип. Можно параметризовать один компонент.

---

### 3.5 BankLogoPicker — дублируется между AccountEditView и DepositEditView

`BankLogoPickerView` определён в `AccountsManagementView.swift` (строка 287), но используется из двух разных файлов:
- `AccountsManagementView.swift:281`
- `DepositEditView.swift:163`

Это **нарушение организации** — компонент, используемый из разных файлов, должен лежать в `Views/Components/`.

---

### 3.6 Hardcoded empty states vs AppEmptyState

В нескольких местах inline VStack с текстом воспроизводит паттерн, который есть как `EmptyStateView` в management views:

- `ContentView` accountsSection (строка 438–452): VStack { title + "Нет счетов" } — inline, без ActionButton
- `ContentView` analyticsCard (строка 495–509): VStack { "История" + "Нет транзакций" } — inline
- `SubscriptionsCardView` (строки 32–35): inline "Нет активных подписок"
- `QuickAddTransactionView` (строки 28–47): inline "Нет категорий"

Все эти блоки — варианты одного паттерна. `AppEmptyState` из `Utils/` или `EmptyStateView` существует, но используется только в management screens.

---

## 4. Нарушения SRP

### 4.1 Компоненты с зависимостями на ViewModel (тянут данные сами)

| Component | File | ViewModels | Проблема |
|-----------|------|-----------|----------|
| `TransactionCard` | `TransactionCard.swift` | `TransactionsViewModel?`, `CategoriesViewModel?` | Может edit/delete транзакции, stop recurring series — бизнес-логика в View |
| `SubscriptionCard` | `SubscriptionCard.swift` | `SubscriptionsViewModel`, `TransactionsViewModel` | Вычисляет next charge date, status indicator из ViewModel |
| `CategoryFilterView` | `CategoryFilterView.swift` | `TransactionsViewModel` | Применяет фильтр напрямую через `viewModel.selectedCategoryFilter = ...` |
| `CategoryFilterButton` | `CategoryFilterButton.swift` | `TransactionsViewModel`, `CategoriesViewModel` | Читает текущий фильтр для адаптивной иконки |
| `HistoryFilterSection` | `HistoryFilterSection.swift` | `TransactionsViewModel`, `AccountsViewModel`, `CategoriesViewModel`, `TimeFilterManager` | Тянет 4 зависимости для проксирования фильтров |
| `SubcategorySelectorView` | `SubcategorySelectorView.swift` | `CategoriesViewModel` | Вычисляет available subcategories + link logic |
| `DepositTransferView` | `DepositTransferView.swift` | `TransactionsViewModel`, `AccountsViewModel` | Выполняет save transfer — full write operation |
| `DepositRateChangeView` | `DepositRateChangeView.swift` | `DepositsViewModel` | Выполняет save rate change — full write operation |
| `SubscriptionsCardView` | `SubscriptionsCardView.swift` | `SubscriptionsViewModel`, `TransactionsViewModel` | Вычисляет total с currency conversion — async бизнес-логика |

### 4.2 Компоненты с бизнес-логикой внутри body

| Component | File | Бизнес-логика |
|-----------|------|---------------|
| `TransactionCard` | `TransactionCard.swift` | Currency conversion logic, recurring series stop with future occurrence deletion, complex amountText computed property |
| `SubscriptionCalendarView` | `SubscriptionCalendarView.swift` | Calendar generation, subscription date filtering, weekday calculations |
| `AmountInputView` | `AmountInputView.swift` | Number formatting, currency stripping, decimal validation, animated font size calculations |
| `AccountRow` | `AccountRow.swift` | Calls `DepositInterestService.calculateInterestToToday()` — Service вызов в View |
| `HighlightedText` | `HighlightedText.swift` | AttributedString generation, confidence-based color mapping |
| `SiriWaveView` | `SiriWaveView.swift` | Mathematical wave path generation (Canvas) — допустимо для визуальной анимации |
| `CategoryChip` | `CategoryChip.swift` | Budget progress ring rendering logic — допустимо (визуализация данных) |

### 4.3 Тяжёлые инлайн-компоненты (>100 строк в файле экрана)

| Component | Parent File | Строки | Проблема |
|-----------|------------|--------|----------|
| `AccountEditView` | `AccountsManagementView.swift` | ~110 строк (176–287) | Full form с bank logo picker, balance input, currency |
| `CategoryEditView` | `CategoriesManagementView.swift` | ~260 строк (139–400) | Самый большой: form + color picker + icon picker + subcategory + budget |
| `AddTransactionModal` | `QuickAddTransactionView.swift` | >200 строк | Full transaction form + account/category selectors |
| `RecognizedTextView` | `ContentView.swift` | ~120 строк (599–720) | Self-contained modal, не зависит от ContentView |

### 4.4 Бесконтролируемый мутатор в скрытом месте

`ContentView.swift` (строки 260–271): `onSave` closure для `AccountEditView` напрямую вызывает:
```swift
accountsViewModel.addAccount(...)
viewModel.accounts = accountsViewModel.accounts  // sync
viewModel.recalculateAccountBalances()
viewModel.saveToStorage()
```
Аналогичный блок в `AccountsManagementView.swift` (строки 96–103).

Это **sync-логика между ViewModels, дублируемая в двух местах** — нарушение DRY. Должна быть extracted в метод `AppCoordinator.addAccount(...)` или аналогичный.

---

## Сводка: приоритетные улучшения

### P0 — Немедленно (нарушение организации файлов)
1. Вынести `RecognizedTextView` из ContentView.swift в `Views/RecognizedTextView.swift`
2. Вынести `ErrorMessageView` из ContentView.swift в `Views/Components/ErrorMessageView.swift`
3. Вынести `AccountEditView` из AccountsManagementView.swift в `Views/AccountEditView.swift`
4. Вынести `CategoryEditView` из CategoriesManagementView.swift в `Views/CategoryEditView.swift`
5. Вынести `BankLogoPickerView` из AccountsManagementView.swift в `Views/Components/BankLogoPickerView.swift`

### P1 — Компонентизация (дубли UI)
6. Создать `EditSheetContainer` — wrapper для edit form shell (5 дублей)
7. Создать generic `ManagementRow` — для accountRow / categoryRow / subcategoryRow (3 дубля)
8. Стандартизировать empty state — использовать один компонент для всех inline empty states

### P2 — SRP (бизнес-логика из View)
9. `TransactionCard` — вынести edit/delete/stop-recurring в ViewModel call, остать View thin
10. `SubscriptionsCardView` — вынести currency conversion total в ViewModel computed property
11. Дублированная sync-логика (`addAccount` в ContentView + AccountsManagementView) → один метод в AppCoordinator
12. `AccountRow` — убрать прямой вызов `DepositInterestService`, передавать pre-calculated data
