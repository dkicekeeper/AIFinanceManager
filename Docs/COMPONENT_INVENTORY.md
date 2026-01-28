# COMPONENT_INVENTORY.md
## AIFinanceManager — Полный реестр UI-компонентов

> **Дата:** 2026-01-28 | **Метод:** статический анализ кода (grep + read всех .swift файлов)
> **Последнее обновление:** 2026-01-28 — выполнен рефакторинг P0/P1/P2 (см. [Сводка изменений](#сводка-изменений))

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
| `SubscriptionsCardView` | `Views/SubscriptionsCardView.swift` | Сводочная карточка подписок на home — сумма + иконки подписок. ✅ **P2#12:** currency conversion делегирована в `SubscriptionsViewModel.calculateTotalInCurrency()` | (зависимости ниже) | — | `ContentView` через `subscriptionsNavigationLink` |

### 1.2 Rows (строки списков)

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `AccountRow` | `Views/Components/AccountRow.swift` | Строка счёта в management list — логотип + имя + баланс + deposit info + swipe delete. ✅ **P2#11:** `DepositInterestService` вызовы заменены на props `interestToday: Double?`, `nextPostingDate: Date?` | `account: Account`, `currency: String`, `onEdit: () -> Void`, `onDelete: () -> Void`, `interestToday: Double?`, `nextPostingDate: Date?` | `onEdit`, `onDelete` | `AccountsManagementView` |
| `CategoryRow` | `Views/Components/CategoryRow.swift` | Строка категории — иконка + имя + budget progress ring + swipe edit/delete | `category: CustomCategory`, `isDefault: Bool`, `budgetProgress: BudgetProgress?`, `onEdit: () -> Void`, `onDelete: () -> Void` | `onEdit`, `onDelete` | `CategoriesManagementView` |
| `SubcategoryRow` | `Views/Components/SubcategoryRow.swift` | Строка подкатегории в selector — имя + checkmark | `subcategory: Subcategory`, `@Binding isSelected: Bool`, `onToggle: () -> Void` | `onToggle` | (только через `SubcategorySelectorView` внутренний loop) |
| `DepositTransactionRow` | `Views/Components/DepositTransactionRow.swift` | Строка транзакции в deposit detail — type-icon + дата + сумма с цветом | `transaction: Transaction`, `currency: String`, `depositAccountId: String` | — | `DepositDetailView` |
| `BankLogoRow` | `Views/Components/BankLogoRow.swift` | Строка банковского логотипа в picker — логотип + имя + selection indicator | `bank: BankLogo`, `isSelected: Bool`, `onSelect: () -> Void` | `onSelect` | `BankLogoPickerView` |
| `InfoRow` | `Views/Components/InfoRow.swift` | Строка label + value — двухколоночный row для detail screens | `label: String`, `value: String` | — | `DepositDetailView`, `SubscriptionDetailView` |
| `TransactionCard` | `Views/Components/TransactionCard.swift` | Основная строка транзакции в history — иконка + описание + сумма + account info + swipe edit/stop recurring. ✅ **P2#10:** stop-recurring logic вынесена в `TransactionsViewModel.stopRecurringSeriesAndCleanup()` | `transaction: Transaction`, `currency: String`, `customCategories: [CustomCategory]`, `accounts: [Account]`, `viewModel: TransactionsViewModel?`, `categoriesViewModel: CategoriesViewModel?` | — (edit modal + stop recurring via internal state) | `HistoryTransactionsList` (строка 90) |

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
| `AmountInputView` | `Views/Components/AmountInputView.swift` | Поле суммы с анимированными цифрами + currency selector | `@Binding amount: String`, `@Binding selectedCurrency: String`, `errorMessage: String?`, `onAmountChange: ((String) -> Void)?` | `onAmountChange` | `QuickAddTransactionView`, `EditTransactionView`, `AccountActionView`, `VoiceInputConfirmationView` |
| `DateButtonsView` | `Views/Components/DateButtonsView.swift` | Кнопки today/yesterday + full date picker | `@Binding selectedDate: Date`, `isDisabled: Bool`, `onSave: (Date) -> Void` | `onSave` | (встроен в edit forms через DatePicker) |
| `DescriptionTextField` | `Views/Components/DescriptionTextField.swift` | Многострочное поле описания с лимитом строк | `@Binding text: String`, `placeholder: String`, `minLines: Int`, `maxLines: Int` | — | `AccountActionView`, `VoiceInputConfirmationView`, `QuickAddTransactionView`, `EditTransactionView` |
| `AccountSelectorView` | `Views/Components/AccountSelectorView.swift` | Modal выбора счёта — список radio buttons + empty/warning states | `accounts: [Account]`, `@Binding selectedAccountId: String?`, `onSelectionChange: ((String?) -> Void)?`, `emptyStateMessage: String?`, `warningMessage: String?` | `onSelectionChange` | `EditTransactionView`, `AccountActionView`, `QuickAddTransactionView`, `VoiceInputConfirmationView` |
| `CategorySelectorView` | `Views/Components/CategorySelectorView.swift` | Modal выбора категории — grid chips + empty/warning + budget map | `categories: [String]`, `type: TransactionType`, `customCategories: [CustomCategory]`, `@Binding selectedCategory: String?`, `onSelectionChange: ((String?) -> Void)?`, `emptyStateMessage: String?`, `warningMessage: String?`, `budgetProgressMap: [String: BudgetProgress]?`, `budgetAmountMap: [String: Double]?` | `onSelectionChange` | `EditTransactionView`, `AccountActionView`, `VoiceInputConfirmationView` |
| `SubcategorySelectorView` | `Views/Components/SubcategorySelectorView.swift` | Modal выбора подкатегорий — list + search link | `categoriesViewModel: CategoriesViewModel`, `categoryId: String?`, `@Binding selectedSubcategoryIds: Set<String>`, `onSearchTap: () -> Void` | `onSearchTap` | `EditTransactionView`, `QuickAddTransactionView`, `VoiceInputConfirmationView` |
| `CurrencySelectorView` | `Views/Components/CurrencySelectorView.swift` | Menu выбора валюты | `@Binding selectedCurrency: String`, `availableCurrencies: [String]` | (binding) | `AmountInputView` (строка 75) |
| `SegmentedPickerView<T>` | `Views/Components/SegmentedPickerView.swift` | Generic обёртка для Picker с segmented style | `title: String`, `@Binding selection: T`, `options: [(label: String, value: T)]` | (binding) | `AccountActionView`, `VoiceInputConfirmationView` |
| `IconPickerView` | `Views/Components/IconPickerView.swift` | Grid выбора SF Symbol иконки | `@Binding selectedIconName: String` | (binding + dismiss) | `SubscriptionEditView`, `CategoryEditView` |

### 1.5 Filters

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `HistoryFilterSection` | `Views/Components/HistoryFilterSection.swift` | Контейнер фильтров history — account menu + category button + text search | `transactionsViewModel`, `accountsViewModel`, `categoriesViewModel`, `timeFilterManager`, `@Binding selectedAccountFilter: String?`, `@Binding showingCategoryFilter: Bool` | (bindings) | `HistoryView` (строка 72) |
| `AccountFilterMenu` | `Views/Components/AccountFilterMenu.swift` | Menu фильтрации по счёту | `accounts: [Account]`, `@Binding selectedAccountId: String?` | (binding) | `HistoryFilterSection` (строка 29) |
| `CategoryFilterView` | `Views/Components/CategoryFilterView.swift` | Modal multi-select фильтрации по категориям | `viewModel: TransactionsViewModel` | (dismiss + filter state) | `HistoryView` (строка 128) |

### 1.6 Empty / Error / Loading states

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `EmptyStateView` | `Views/Components/EmptyStateView.swift` | Стандартный пустой состояний — иконка + текст + optional action | `icon: String`, `title: String`, `description: String`, `actionTitle: String?`, `action: (() -> Void)?` | `action` | `AccountsManagementView`, `CategoriesManagementView`, `SubcategoriesManagementView` |
| `ErrorMessageView` | `Views/Components/ErrorMessageView.swift` | Баннер ошибки — иконка + текст. ✅ **P0#2:** вынесен из ContentView.swift | `message: String` | — | `ContentView` |
| `WarningMessageView` | `Views/Components/WarningMessageView.swift` | Баннер предупреждения — иконка + текст | `message: String`, `color: Color` | — | `AccountSelectorView`, `CategorySelectorView` |
| `SkeletonView` | `Views/Components/SkeletonView.swift` | Loading placeholder анимация | (нет — все параметры закомментированы) | — | (не используется снаружи, только внутренние скелетоны) |

### 1.7 Containers / Layouts

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `EditSheetContainer<Content>` | `Views/Components/EditSheetContainer.swift` | ✅ **P1#6:** Generic обёртка edit-form sheet — NavigationView + Form + toolbar (xmark / checkmark). Устранил 5 дублей | `title: String`, `isSaveDisabled: Bool`, `onSave: () -> Void`, `onCancel: () -> Void`, `@ViewBuilder content` | `onSave`, `onCancel` | `AccountEditView`, `CategoryEditView`, `SubcategoryEditView`, `DepositEditView`, `SubscriptionEditView` |
| `ExpenseIncomeProgressBar` | `Views/Components/ExpenseIncomeProgressBar.swift` | Двойной progress bar income/expense | `expenseAmount: Double`, `incomeAmount: Double`, `currency: String` | — | `AnalyticsCard` (строка 25) |

### 1.8 Specialized / Helpers

| Component | File | Responsibility | Inputs | Outputs/Actions | Used in |
|-----------|------|----------------|--------|-----------------|---------|
| `SiriWaveView` | `Views/Components/SiriWaveView.swift` | Анимация волны для voice recording | `amplitude: Double`, `frequency: Double`, `color: Color`, `animationSpeed: Double` | — | `VoiceInputView` |
| `HighlightedText` | `Views/Components/HighlightedText.swift` | Текст с подсвеченными entity (NLP output) | `text: String`, `entities: [RecognizedEntity]`, `font: Font` | — | `VoiceInputView` (строка 40) |
| `BrandLogoView` | `Views/Components/BrandLogoView.swift` | Логотип бренда через logo.dev API + async cache | `brandName: String?`, `size: CGFloat` | — | `SubscriptionCard`, `SubscriptionCalendarView`, `StaticSubscriptionIconsView`, `SubscriptionDetailView` |
| `StaticSubscriptionIconsView` | `Views/Components/StaticSubscriptionIconsView.swift` | Overlapping иконки подписок (как stack аватаров) | `subscriptions: [RecurringSeries]` | — | `SubscriptionsCardView` |
| `SubscriptionCalendarView` | `Views/Components/SubscriptionCalendarView.swift` | Calendar grid с подписками по дням месяца | `subscriptions: [RecurringSeries]` | — | `SubscriptionsListView` (строка 21) |
| `BankLogoPickerView` | `Views/Components/BankLogoPickerView.swift` | ✅ **P0#5:** Вынесен из AccountsManagementView. Modal выбора логотипа банка — popular / other / none sections | `@Binding selectedLogo: BankLogo` | (binding + dismiss) | `AccountEditView`, `DepositEditView` |

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

| Struct | Defined in | Line | Parameters | Used in | Статус |
|--------|-----------|------|------------|---------|--------|
| `RecognizedTextView` | `Views/RecognizedTextView.swift` | — | `recognizedText: String`, `structuredRows: [[String]]?`, `viewModel: TransactionsViewModel`, `onImport: (CSVFile) -> Void`, `onCancel: () -> Void` | `ContentView` | ✅ **P0#1:** Вынесен из ContentView.swift |
| `ErrorMessageView` | `Views/Components/ErrorMessageView.swift` | — | `message: String` | `ContentView` | ✅ **P0#2:** Вынесен из ContentView.swift |
| `AccountEditView` | `Views/AccountEditView.swift` | — | `accountsViewModel: AccountsViewModel`, `transactionsViewModel: TransactionsViewModel`, `account: Account?`, `onSave: (Account) -> Void`, `onCancel: () -> Void` | `ContentView`, `AccountsManagementView` | ✅ **P0#3:** Вынесен из AccountsManagementView.swift. Использует `EditSheetContainer` (P1#6) |
| `BankLogoPickerView` | `Views/Components/BankLogoPickerView.swift` | — | `@Binding selectedLogo: BankLogo` | `AccountEditView`, `DepositEditView` | ✅ **P0#5:** Вынесен из AccountsManagementView.swift |
| `CategoryEditView` | `Views/CategoryEditView.swift` | — | `categoriesViewModel`, `transactionsViewModel`, `category: CustomCategory?`, `type: TransactionType`, `onSave: (CustomCategory) -> Void`, `onCancel: () -> Void` | `QuickAddTransactionView`, `CategoriesManagementView` | ✅ **P0#4:** Вынесен из CategoriesManagementView.swift. Использует `EditSheetContainer` (P1#6) |
| `SubcategoryManagementRow` | `SubcategoriesManagementView.swift` | 82 | `subcategory: Subcategory`, `onEdit: () -> Void`, `onDelete: () -> Void` | `SubcategoriesManagementView` | 🔄 Открыто — структура аналогична `AccountRow` / `CategoryRow` (см. P1#8 ниже) |
| `SubcategoryEditView` | `SubcategoriesManagementView.swift` | 106 | `categoriesViewModel: CategoriesViewModel`, `subcategory: Subcategory?`, `onSave: (Subcategory) -> Void`, `onCancel: () -> Void` | `SubcategoriesManagementView` | ✅ **P1#6:** Рефакторинг — теперь использует `EditSheetContainer` (остаётся в tom же файле) |
| `AddTransactionModal` | `QuickAddTransactionView.swift` | ~111 | `category: String`, `type: TransactionType`, `currency: String`, `accounts: [Account]`, 3 ObservedObjects, `onDismiss: () -> Void` | `QuickAddTransactionView` | 🔄 Открыто — большой (>200 строк), содержит бизнес-логику |
| `TransactionRow` | `SubscriptionDetailView.swift` | 321 | `transaction: Transaction`, `viewModel: TransactionsViewModel`, `isPlanned: Bool` | `SubscriptionDetailView` | 🔄 Открыто — **Дубль** аналогичен `DepositTransactionRow` |
| `AccountMappingDetailView` | `CSVEntityMappingView.swift` | 245 | `csvValue: String`, `accounts: [Account]`, `@Binding selectedAccountId: String?`, `onCreateNew: () -> Void` | `CSVEntityMappingView` | CSV-specific, может остаться |
| `CategoryMappingDetailView` | `CSVEntityMappingView.swift` | 284 | `csvValue: String`, `categories: [CustomCategory]`, `categoryType: TransactionType`, `@Binding selectedCategoryName: String?`, `onCreateNew: () -> Void` | `CSVEntityMappingView` | CSV-specific, может остаться |
| `LogoSearchResultRow` | `LogoSearchView.swift` | 235 | `result: LogoSearchResult`, `isSelected: Bool`, `onSelect: () -> Void` | `LogoSearchView` | Feature-specific, может остаться |
| `TransactionPreviewRow` | `TransactionPreviewView.swift` | 162 | `transaction: Transaction`, `isSelected: Bool`, `selectedAccountId: String?`, `availableAccounts: [Account]`, `onToggle: () -> Void`, `onAccountSelect: (String) -> Void` | `TransactionPreviewView` | Feature-specific, может остаться |
| `StatRow` | `CSVImportResultView.swift` | — | `label: String`, `value: String`, `color: Color`, `icon: String?` | `CSVImportResultView` | 🔄 Аналогичен `InfoRow` — может использовать InfoRow |
| `DatePickerSheet` | `QuickAddTransactionView.swift` | — | `@Binding selectedDate: Date`, `onDateSelected: (Date) -> Void` | `QuickAddTransactionView` | 🔄 Дубль date picker sheet |
| `RecordingIndicatorView` | `VoiceInputView.swift` | 223 | (none — internal animation state) | `VoiceInputView` | Feature-specific, может остаться |

---

## 3. Дубли UI

### 3.1 Edit Form Shell (NavigationView + Form + toolbar Save/Cancel)

> ✅ **P1#6: COMPLETED** — Устранён созданием `EditSheetContainer<Content: View>` в `Views/Components/EditSheetContainer.swift`

Все пять edit-view рефакторированы:

| View | File | Статус |
|------|------|--------|
| `AccountEditView` | `Views/AccountEditView.swift` | ✅ Использует `EditSheetContainer` |
| `CategoryEditView` | `Views/CategoryEditView.swift` | ✅ Использует `EditSheetContainer` |
| `SubcategoryEditView` | `SubcategoriesManagementView.swift` | ✅ Использует `EditSheetContainer` |
| `DepositEditView` | `Views/DepositEditView.swift` | ✅ Использует `EditSheetContainer` |
| `SubscriptionEditView` | `Views/SubscriptionEditView.swift` | ✅ Использует `EditSheetContainer` |

**Реализация:**
```swift
struct EditSheetContainer<Content: View>: View {
    let title: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationView {
            Form { content() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { HapticManager.light(); onSave() } label: { Image(systemName: "checkmark") }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
}
```

---

### 3.2 Management List Shell (EmptyState + List + toolbar +)

| View | File | Pattern |
|------|------|---------|
| `AccountsManagementView` | `AccountsManagementView.swift` | Empty → EmptyStateView \| List → ForEach → Row(onEdit/onDelete) |
| `CategoriesManagementView` | `CategoriesManagementView.swift` | Empty → EmptyStateView \| List → ForEach → Row(onEdit/onDelete) |
| `SubcategoriesManagementView` | `SubcategoriesManagementView.swift` | Empty → EmptyStateView \| List → ForEach → Row(onEdit/onDelete) |

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

> 🔄 **P1#8: OPEN** — Generic `ManagementRow` с `leading: some View`, `trailing: some View?`, `onEdit`, `onDelete` создан **не был**. Причина: три row имеют слишком различный trailing content (deposit badge + interest info vs budget ring vs минимум). Generic обёртка была бы слишком тонкой, чтобы покрыть все кейсы без значительной потери ясности.

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

### 3.5 BankLogoPicker

> ✅ **P0#5: COMPLETED** — `BankLogoPickerView` вынесен в `Views/Components/BankLogoPickerView.swift`

Компонент теперь в стандартном месте, доступен из `AccountEditView` и `DepositEditView` без нарушения организации файлов.

---

### 3.6 Hardcoded empty states vs EmptyStateView

> 🔄 **P1#7: OPEN** — Стандартизация НЕ была реализована.

Причина: inline VStack в card-контекстах (home screen) визуально отличаются от management-`EmptyStateView` — нет иконки, нет action-кнопки, меньше padding. Механическая замена привела бы к визуальной регрессии.

| Место | Текущее состояние |
|-------|-------------------|
| `ContentView` accountsSection | Inline VStack «Нет счетов» — без action |
| `ContentView` analyticsCard | Inline VStack «Нет транзакций» |
| `SubscriptionsCardView` | Inline «Нет активных подписок» |
| `QuickAddTransactionView` | Inline «Нет категорий» |

**Рекомендация для будущей работы:** Создать лёгкую вариацию `EmptyStateView(style: .compact)` без иконки и action для card-контекстов.

---

## 4. Нарушения SRP

### 4.1 Компоненты с зависимостями на ViewModel (тянут данные сами)

| Component | File | ViewModels | Статус |
|-----------|------|-----------|--------|
| `TransactionCard` | `TransactionCard.swift` | `TransactionsViewModel?`, `CategoriesViewModel?` | ✅ **P2#10:** stop-recurring вынесен в `TransactionsViewModel.stopRecurringSeriesAndCleanup()` |
| `SubscriptionCard` | `SubscriptionCard.swift` | `SubscriptionsViewModel`, `TransactionsViewModel` | 🔄 Вычисляет next charge date, status indicator из ViewModel |
| `CategoryFilterView` | `CategoryFilterView.swift` | `TransactionsViewModel` | 🔄 Применяет фильтр напрямую через `viewModel.selectedCategoryFilter = ...` |
| `CategoryFilterButton` | `CategoryFilterButton.swift` | `TransactionsViewModel`, `CategoriesViewModel` | 🔄 Читает текущий фильтр для адаптивной иконки |
| `HistoryFilterSection` | `HistoryFilterSection.swift` | `TransactionsViewModel`, `AccountsViewModel`, `CategoriesViewModel`, `TimeFilterManager` | 🔄 Тянет 4 зависимости для проксирования фильтров |
| `SubcategorySelectorView` | `SubcategorySelectorView.swift` | `CategoriesViewModel` | 🔄 Вычисляет available subcategories + link logic |
| `DepositTransferView` | `DepositTransferView.swift` | `TransactionsViewModel`, `AccountsViewModel` | 🔄 Выполняет save transfer — full write operation |
| `DepositRateChangeView` | `DepositRateChangeView.swift` | `DepositsViewModel` | 🔄 Выполняет save rate change — full write operation |
| `SubscriptionsCardView` | `SubscriptionsCardView.swift` | `SubscriptionsViewModel`, `TransactionsViewModel` | ✅ **P2#12:** currency conversion total делегирована в `SubscriptionsViewModel.calculateTotalInCurrency()` |

### 4.2 Компоненты с бизнес-логикой внутри body

| Component | File | Бизнес-логика | Статус |
|-----------|------|---------------|--------|
| `TransactionCard` | `TransactionCard.swift` | Recurring series stop + future occurrence deletion | ✅ **P2#10:** Вынесен в `TransactionsViewModel.stopRecurringSeriesAndCleanup(seriesId:transactionDate:)` |
| `SubscriptionCalendarView` | `SubscriptionCalendarView.swift` | Calendar generation, subscription date filtering, weekday calculations | 🔄 Допустимо для presentation-heavy компонента |
| `AmountInputView` | `AmountInputView.swift` | Number formatting, currency stripping, decimal validation, animated font size calculations | 🔄 Допустимо — presentation logic |
| `AccountRow` | `AccountRow.swift` | ~~Calls `DepositInterestService.calculateInterestToToday()`~~ | ✅ **P2#11:** Service вызовы заменены на props `interestToday: Double?`, `nextPostingDate: Date?`. Родитель (`AccountsManagementView`) вычисляет и передаёт |
| `HighlightedText` | `HighlightedText.swift` | AttributedString generation, confidence-based color mapping | 🔄 Допустимо — presentation logic |
| `SiriWaveView` | `SiriWaveView.swift` | Mathematical wave path generation (Canvas) | Допустимо для визуальной анимации |
| `CategoryChip` | `CategoryChip.swift` | Budget progress ring rendering logic | Допустимо — визуализация данных |

### 4.3 Тяжёлые инлайн-компоненты (>100 строк в файле экрана)

| Component | Текущий файл | Статус |
|-----------|-------------|--------|
| `AccountEditView` | `Views/AccountEditView.swift` | ✅ **P0#3:** Вынесен. ~100 строк, clean form |
| `CategoryEditView` | `Views/CategoryEditView.swift` | ✅ **P0#4:** Вынесен. ~240 строк, self-contained |
| `AddTransactionModal` | `QuickAddTransactionView.swift` | 🔄 Открыто — >200 строк, содержит бизнес-логику |
| `RecognizedTextView` | `Views/RecognizedTextView.swift` | ✅ **P0#1:** Вынесен. ~120 строк, self-contained |

### 4.4 Sync-логика между ViewModels

> ✅ **P2#9: COMPLETED**

**Было:** 3 копии ручной sync в ContentView + AccountsManagementView:
```swift
accountsViewModel.addAccount(...)
viewModel.accounts = accountsViewModel.accounts  // manual sync
viewModel.recalculateAccountBalances()
viewModel.saveToStorage()
```

**Теперь:** Один метод в `TransactionsViewModel`:
```swift
func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) {
    accounts = accountsViewModel.accounts
    recalculateAccountBalances()
    saveToStorage()
}
```
Все 3 call-site заменены на `transactionsViewModel.syncAccountsFrom(accountsViewModel)`.

---

## Сводка: приоритетные улучшения

### ✅ Завершены (P0 + P1#6 + P2#9–12)

| № | Задача | Результат |
|---|--------|-----------|
| P0#1 | Вынести `RecognizedTextView` | `Views/RecognizedTextView.swift` |
| P0#2 | Вынести `ErrorMessageView` | `Views/Components/ErrorMessageView.swift` |
| P0#3 | Вынести `AccountEditView` | `Views/AccountEditView.swift` + `EditSheetContainer` |
| P0#4 | Вынести `CategoryEditView` | `Views/CategoryEditView.swift` + `EditSheetContainer` |
| P0#5 | Вынести `BankLogoPickerView` | `Views/Components/BankLogoPickerView.swift` |
| P1#6 | `EditSheetContainer` generic wrapper | `Views/Components/EditSheetContainer.swift` — 5 edit-views рефакторированы |
| P2#9 | Sync-логика → один метод | `TransactionsViewModel.syncAccountsFrom()` — 3 call-site |
| P2#10 | TransactionCard stop-recurring | `TransactionsViewModel.stopRecurringSeriesAndCleanup()` |
| P2#11 | AccountRow — убрать DepositInterestService | Props `interestToday` / `nextPostingDate` из родителя |
| P2#12 | SubscriptionsCardView — currency conversion | `SubscriptionsViewModel.calculateTotalInCurrency()` |

### 🔄 Открыты (оложены / менее критичны)

| № | Задача | Обоснование |
|---|--------|-------------|
| P1#7 | Стандартизация inline empty states | Card-контексты на home визуально отличаются от management EmptyStateView. Рекомендация: `EmptyStateView(style: .compact)` |
| P1#8 | Generic `ManagementRow` | Row-компоненты слишком различаются в trailing content для полезной generic обёртки |

### 🔄 Открыты (не в текущем скопе)

| № | Задача |
|---|--------|
| — | `AddTransactionModal` — вынести из QuickAddTransactionView (>200 строк) |
| — | `TransactionRow` в SubscriptionDetailView — дубль DepositTransactionRow |
| — | `SubscriptionCard` — вычисление next charge date из ViewModel |
| — | `DepositTransferView` / `DepositRateChangeView` — full write operations из View |
