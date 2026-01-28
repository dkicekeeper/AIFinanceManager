# AIFinanceManager — Project Bible

> **Дата создания:** 2026-01-28
> **Версия:** 1.0
> **Автор:** AI Architecture Audit
> **Статус:** Актуальный для main ветки

---

## 1. Общая идея проекта

**AIFinanceManager** — iOS приложение для персонального управления финансами, построенное на Swift / SwiftUI.

### Основная ценность
Позволяет пользователю отслеживать доходы и расходы по нескольким счетам с поддержкой многовалютности, автоматического импорта из bank statements (PDF), голосового ввода транзакций и периодических платежей (subscriptions/recurring).

### Ключевые сценарии
1. **Ручной ввод транзакций** — через QuickAdd (сетка категорий) или голосовой ввод
2. **Импорт из PDF/CSV** — OCR распознавание PDF выписок банка, затем маппинг полей
3. **Отслеживание subscriptions** — повторяющиеся платежи с уведомлениями и календарём
4. **Депозиты** — счета с начислением процентов, капитализация, история ставок
5. **Аналитика** — сводка доходов/расходов по периодам, бюджеты на категории
6. **Многовалютность** — конвертация суммы при разных валютах счёта и транзакции

---

## 2. Архитектура проекта

### Общая схема: MVVM с Coordinator

```
┌─────────────────────────────────────────────────────────┐
│  AIFinanceManagerApp (@main)                            │
│    └── ContentView                                      │
│         ├── @EnvironmentObject TimeFilterManager        │
│         └── @EnvironmentObject AppCoordinator           │
│              │                                          │
│              ├── AccountsViewModel                      │
│              ├── CategoriesViewModel                    │
│              ├── SubscriptionsViewModel                 │
│              ├── DepositsViewModel (зависит от Accounts)│
│              └── TransactionsViewModel (зависит от Accounts) │
│                                                         │
│  Services Layer                                         │
│    ├── CoreDataRepository (primary)                     │
│    ├── UserDefaultsRepository (fallback)                │
│    ├── BalanceCalculationService                        │
│    ├── DepositInterestService                           │
│    ├── CSVImportService                                 │
│    ├── VoiceInputService                                │
│    └── ... (26 сервисов)                                │
│                                                         │
│  Data Layer                                             │
│    ├── CoreData (primary persistence)                   │
│    └── UserDefaults (fallback + settings)               │
└─────────────────────────────────────────────────────────┘
```

### Поток данных
```
User Action
  → View (SwiftUI)
    → ViewModel (@Published triggers)
      → Service (business logic)
        → Repository (DataRepositoryProtocol)
          → CoreData / UserDefaults
            → Repository returns data
          → ViewModel updates @Published
        → SwiftUI re-renders
```

### Где бизнес-логика
- **Расчёт баланса:** `BalanceCalculationService` + `BalanceCalculator` (actor)
- **Проценты по депозитам:** `DepositInterestService`
- **Фильтрация транзакций:** `TransactionFilterService`
- **Группировка:** `TransactionGroupingService`
- **Генерация recurring:** `RecurringTransactionGenerator`
- **Импорт CSV:** `CSVImportService`
- **Ранжирование счётов:** `AccountRankingService`

### SRP в проекте
- ViewModel ≠ Service. ViewModels управляют состоянием UI, Services содержат алгоритмы.
- `TransactionsViewModel` — ИСКЛЮЧЕНИЕ: он слишком большой (~103KB), содержит кэш-менеджмент, batch-mode логику и координацию между сервисами. Это **знаемый долг**.
- `AppCoordinator` отвечает за DI и инициализацию ViewModels в правильном порядке зависимостей.

---

## 3. Структура проекта

```
AIFinanceManager/
├── AIFinanceManagerApp.swift          # Entry point (@main)
├── Info.plist                         # App config
│
├── CoreData/                          # Persistence layer
│   ├── CoreDataStack.swift            # Singleton container + contexts
│   ├── CoreDataIndexes.swift          # Fetch optimization
│   ├── CoreDataSaveCoordinator.swift  # Thread-safe save (actor)
│   └── Entities/                      # 10 entities × 2 files (Class + Properties)
│
├── Models/                            # Domain models (Codable structs)
│   ├── Transaction.swift              # Transaction, Account, DepositInfo, Summary
│   ├── RecurringTransaction.swift     # RecurringSeries, RecurringOccurrence
│   ├── CustomCategory.swift           # CustomCategory + budget
│   ├── Subcategory.swift              # Subcategory + link models
│   ├── AppSettings.swift              # App-level settings (ObservableObject)
│   ├── BudgetProgress.swift           # Budget status DTO
│   ├── TimeFilter.swift               # Time range presets
│   ├── CSVColumnMapping.swift         # CSV import config
│   └── ParsedOperation.swift          # Voice input DTO
│
├── Protocols/                         # Abstractions
│   └── AccountBalanceServiceProtocol  # Decouples TxnVM from AccountsVM
│
├── Services/                          # Business logic + data access
│   ├── DataRepositoryProtocol.swift   # Persistence abstraction
│   ├── CoreDataRepository.swift       # Primary implementation (~1177 lines)
│   ├── UserDefaultsRepository.swift   # Fallback implementation
│   ├── CoreDataSaveCoordinator.swift  # Concurrency-safe saves
│   ├── BalanceCalculationService.swift # Balance calculation modes
│   ├── BalanceUpdateCoordinator.swift  # Race condition prevention
│   ├── DepositInterestService.swift   # Interest accrual logic
│   ├── TransactionCacheManager.swift  # ✨ NEW: Cache management (summary, balances, indexes)
│   ├── TransactionCurrencyService.swift # ✨ NEW: Currency conversion caching
│   ├── CSVImportService.swift         # CSV parsing + entity creation (~717 lines)
│   ├── CSVImporter.swift / CSVExporter.swift
│   ├── VoiceInputService.swift        # Speech recognition
│   ├── VoiceInputParser.swift         # Text → Transaction parsing
│   ├── StatementTextParser.swift      # Bank statement → CSV
│   ├── AccountRankingService.swift    # Smart account suggestions
│   ├── AccountUsageTracker.swift      # Usage frequency tracking
│   ├── CurrencyConverter.swift        # Multi-currency conversion
│   ├── DataMigrationService.swift     # UserDefaults → CoreData migration
│   ├── LogoService.swift              # Bank logo fetching
│   ├── LogoDiskCache.swift            # Logo caching
│   ├── PDFService.swift               # PDF text extraction
│   ├── SubscriptionNotificationScheduler.swift
│   ├── Audio/SilenceDetector.swift    # VAD for voice input
│   └── ML/CategoryMLPredictor.swift   # ML-based categorization
│
├── Managers/                          # Specialized state managers
│   ├── TimeFilterManager.swift        # Global time filter (@EnvironmentObject)
│   ├── TransactionIndexManager.swift  # O(1) transaction lookups
│   ├── TransactionPaginationManager.swift # Lazy-loading pagination
│   └── DateSectionExpensesCache.swift # Section header expense cache
│
├── ViewModels/                        # Presentation logic
│   ├── AppCoordinator.swift           # DI container + init orchestration
│   ├── AccountsViewModel.swift        # Account CRUD + balance sync
│   ├── CategoriesViewModel.swift      # Categories + budgets
│   ├── SubscriptionsViewModel.swift   # Subscription lifecycle
│   ├── DepositsViewModel.swift        # Deposit interest management
│   ├── TransactionsViewModel.swift    # ⚠️ LARGE: core transaction hub
│   ├── HistoryFilterCoordinator.swift # Filter state + debouncing
│   ├── Balance/BalanceCalculator.swift  # Actor-based balance calc
│   ├── Recurring/RecurringTransactionGenerator.swift
│   └── Transactions/                  # Filter + Grouping services
│       ├── TransactionFilterService.swift
│       └── TransactionGroupingService.swift
│
├── Views/                             # SwiftUI Views
│   ├── ContentView.swift              # Root view (home screen)
│   ├── HistoryView.swift              # Transaction history
│   ├── SettingsView.swift             # App settings
│   ├── QuickAddTransactionView.swift  # Category grid → add transaction
│   ├── EditTransactionView.swift      # Full transaction form
│   ├── AccountsManagementView.swift   # Account CRUD UI
│   ├── CategoriesManagementView.swift # Category CRUD + budget
│   ├── SubcategoriesManagementView.swift
│   ├── SubscriptionsListView.swift    # Subscription grid
│   ├── SubscriptionDetailView.swift
│   ├── SubscriptionEditView.swift
│   ├── DepositDetailView.swift
│   ├── DepositEditView.swift
│   ├── VoiceInputView.swift           # Voice recording UI
│   ├── VoiceInputConfirmationView.swift
│   ├── TimeFilterView.swift           # Date range picker
│   ├── CSV*.swift                     # 4 CSV import workflow screens
│   ├── Components/                    # 39 reusable UI components
│   │   ├── TransactionCard.swift      # Transaction row with swipe
│   │   ├── AccountCard.swift          # Account card (carousel)
│   │   ├── CategoryChip.swift         # Category coin with budget ring
│   │   ├── AnalyticsCard.swift        # Summary card
│   │   ├── SubscriptionCard.swift     # Subscription card
│   │   └── ... (34 more components)
│   └── History/                       # History sub-components
│       ├── HistoryTransactionsList.swift
│       └── HistoryScrollBehavior.swift
│
├── Utils/                             # Cross-cutting utilities
│   ├── AppTheme.swift                 # Design system (spacing, radius, typography, colors)
│   ├── Colors.swift                   # Category color palette
│   ├── CategoryStyleHelper.swift      # Category icon/color resolution
│   ├── CategoryIcon.swift             # Icon name mapping
│   ├── Formatting.swift               # Currency formatting
│   ├── AmountFormatter.swift          # Amount display logic
│   ├── DateFormatters.swift           # Shared date formatters
│   ├── HapticManager.swift            # Haptic feedback
│   ├── TransactionIDGenerator.swift   # Deterministic ID gen
│   ├── PerformanceProfiler.swift      # Timing measurement
│   ├── BankLogo.swift                 # Bank logo enum
│   ├── VoiceInputConstants.swift      # Voice config
│   └── AppButton.swift / AppEmptyState.swift
│
└── Extensions/
    └── Notification+Extensions.swift
```

### Принципы нейминга
- **ViewModels:** `<Feature>ViewModel` (n.ex: `AccountsViewModel`)
- **Views/Screens:** `<Feature>View` или `<Feature><Action>View` (n.ex: `EditTransactionView`)
- **Components:** Noun-based, describes UI element (n.ex: `TransactionCard`, `CategoryChip`)
- **Services:** `<Domain><Action>Service` (n.ex: `BalanceCalculationService`)
- **Models:** PascalCase struct names matching domain (n.ex: `Transaction`, `Account`)

### Для новичка: где начать
1. `AIFinanceManagerApp.swift` — entry point, 2 environment objects
2. `AppCoordinator.swift` — видны все ViewModels и порядок зависимостей
3. `ContentView.swift` — главный экран, навигация
4. `AppTheme.swift` — все дизайн-токены
5. `Transaction.swift` — core модель, все типы транзакций

---

## 4. Data layer / Хранение данных

### Типы данных (core entities)

| Модель | Файл | Описание |
|--------|------|----------|
| `Transaction` | `Models/Transaction.swift` | Основная сущность: расход, доход, перевод, deposit ops |
| `Account` | `Models/Transaction.swift` | Банковский счёт с балансом, валютой, логотипом |
| `DepositInfo` | `Models/Transaction.swift` | Депозит: ставка, капитализация, история ставок |
| `RecurringSeries` | `Models/RecurringTransaction.swift` | Серия повторяющихся транзакций |
| `RecurringOccurrence` | `Models/RecurringTransaction.swift` | Одиночное вхождение серии |
| `CustomCategory` | `Models/CustomCategory.swift` | Категория с бюджетом |
| `Subcategory` | `Models/Subcategory.swift` | Подкатегория + link-таблицы |
| `CategoryRule` | `Models/Transaction.swift` | Правило авто-категоризации |
| `AppSettings` | `Models/AppSettings.swift` | Валюта, обои |
| `TimeFilter` | `Models/TimeFilter.swift` | Пресеты фильтра по времени |

### Хранение
- **Primary:** CoreData (`CoreDataStack.shared`) — все сущности
- **Fallback:** UserDefaults (`UserDefaultsRepository`) — JSON-сериализация через Codable
- **Settings:** UserDefaults напрямую (`AppSettings.save()` / `AppSettings.load()`)
- **Time Filter:** UserDefaults (`TimeFilterManager`)
- **Wallpaper:** File system (`Documents/`)
- **Bank Logos:** Disk cache (`LogoDiskCache`)

### Связи между сущностями
```
Account (1) ──── (N) Transaction          // accountId, targetAccountId
RecurringSeries (1) ── (N) RecurringOccurrence  // seriesId
RecurringSeries (1) ── (N) Transaction    // recurringSeriesId
CustomCategory (1) ── (N) CategorySubcategoryLink ── (1) Subcategory
Transaction (1) ── (N) TransactionSubcategoryLink ── (1) Subcategory
```

### Single Source of Truth
- **Accounts + balances:** `AccountsViewModel.accounts` — единый массив, конвертируется из CoreData
- **Transactions:** `TransactionsViewModel.allTransactions` — полный набор в памяти
- **Categories:** `CategoriesViewModel.customCategories`
- **Time filter:** `TimeFilterManager.currentFilter` (global)
- **Settings:** `AppSettings` (singleton через load/save)

### Миграция
`DataMigrationService` — однократная миграция из UserDefaults → CoreData (версия `coreDataMigrationCompleted_v5`). После миграции UserDefaults исользуется только как fallback при ошибках CoreData.

---

## 5. Бизнес-логика и механики

### Баланс счёта — два режима
```
BalanceCalculationMode:
  .fromInitialBalance   → balance = initialBalance + Σ(transactions)
  .preserveImported     → balance уже содержит все транзакции (CSV import)
```
- `BalanceCalculationService` определяет режим для каждого счёта
- `BalanceCalculator` (actor) — потокобезопасный расчёт
- `BalanceUpdateCoordinator` предотвращает race conditions

### Перевод между счётами
- Создаётся транзакция с `type = .internalTransfer`
- `accountId` = источник, `targetAccountId` = получатель
- `amount` / `currency` — сумма-источник, `targetAmount` / `targetCurrency` — сумма-получатель
- Оба счёта обновляются в одном цикле

### Депозиты и проценты
- Формула: `dailyInterest = principal * (annualRate / 100) / 365`
- Начисление по указанному дню месяца (idempotent по month-fingerprint)
- Капитализация: проценты добавляются к `principalBalance`
- `lastInterestPostingMonth` предотвращает двойное начисление

### Recurring transactions
- `RecurringTransactionGenerator` создаёт транзакции на 3 месяца вперёд
- Частоты: daily, weekly, monthly, yearly
- Occurrence tracking предотвращает дублирование
- При изменении параметров серии (частота, сумма) — удаление future и regeneration

### CSV Import flow
1. PDF → OCR (`PDFService`) → text
2. Text → structured rows (`StatementTextParser`)
3. User mapping (columns → fields) через `CSVPreviewView` / `CSVColumnMappingView`
4. `CSVImportService`: fingerprint dedup, auto-create accounts/categories, batch 500
5. Balance recalculation с `preserveImported` mode

### Voice Input flow
1. `VoiceInputService` — speech recognition (Russian priority, iOS 17+ contextual strings)
2. `VoiceInputParser` — NLP parsing: amount, category, account из текста
3. `VoiceInputConfirmationView` — user review + corrections before save

### Бюджеты
- `CustomCategory.budgetAmount` + `budgetPeriod` (weekly/monthly/yearly) + `budgetResetDay`
- `CategoriesViewModel` рассчитывает spent за текущий период
- `BudgetProgress` DTO — progress, remaining, isOverBudget
- Визуализация: stroke ring на `CategoryChip`

### Фильтрация и группировка
- `TransactionFilterService`: по времени, аккаунту, категории, типу, текstu
- `TransactionGroupingService`: по дате (с "Today"/"Yesterday"), по месяцу, по категории
- `TransactionIndexManager`: индексы по accountId, category, type для O(1) lookup
- `TransactionPaginationManager`: 10 date sections per page, lazy loading

---

## 6. UI / SwiftUI подход

### Общие принципы
- Все View-файлы — **struct View**, без UIKit (кроме `UIImage` для wallpaper/photo)
- **@ObservedObject** для ViewModels, **@EnvironmentObject** для глобальных (TimeFilterManager, AppCoordinator)
- Вычисляемые свойства для вырванных секций UI (n.ex: `private var accountsSection: some View`)
- **`refreshTrigger`** pattern в ContentView для принудительного обновления при nested computed properties

### Layout паттерны
- **Home screen:** ScrollView с VStack секциями + `.safeAreaInset(edge: .bottom)` для persistent actions
- **Horizontal carousel:** `ScrollView(.horizontal)` + `HStack` для accounts
- **Category grid:** `LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))])` в QuickAdd
- **Transaction list:** `List` с `LazyVStack` и pagination
- **Forms:** `Form` + `Section` для edit screens

### Навигация
```
NavigationView (iOS 15 API — НЕ NavigationStack)
  ├── NavigationLink → HistoryView
  ├── NavigationLink → SubscriptionsListView
  ├── NavigationLink → SettingsView
  │    └── NavigationLink → CategoriesManagement / AccountsManagement
  └── .sheet() для модальных: AddTransaction, VoiceInput, CSVImport, TimeFilter
```
**Нет TabView** — приложение использует modal-based навигацию.

### Управление состояниями
- **Loading:** `isInitializing` в ContentView → ProgressView overlay
- **Empty:** Вспроизводимые через `AppEmptyState` компонент + inline empty states (n.ex: accountsSection)
- **Error:** `ErrorMessageView` компонент (красный баннер)
- **Skeleton:** `SkeletonView` для placeholder loading

### SRP в Views
- Screen-level views (ContentView, HistoryView) разбиты на extracted computed properties
- Business logic отделена в Services
- Reusable компоненты в `Components/` (39 штук)

---

## 7. Переиспользуемые UI-компоненты

### Компоненты (Views/Components/)

| Компонент | Использование |
|-----------|---------------|
| `TransactionCard` | Строка транзакции с swipe-actions (History, AccountAction, Deposits) |
| `AccountCard` | Карточка счёта в горизонтальном carousel |
| `CategoryChip` | Coin иконка с budget ring (QuickAdd grid) |
| `AnalyticsCard` | Сводка income/expense с progress bar |
| `SubscriptionCard` | Карточка подписки (grid + home) |
| `FilterChip` | Pill-shaped фильтр (History filters) |
| `CategoryFilterView` | Modal для multi-select по категориям |
| `AccountSelectorView` | Modal выбора счёта |
| `CategorySelectorView` | Modal выбора категории |
| `SubcategorySelectorView` | Modal выбора подкатегорий |
| `AmountInputView` | Поле суммы + currency picker |
| `DateButtonsView` | Date picker интеграция |
| `RecurringToggleView` | Toggle + frequency picker |
| `SegmentedPickerView` | Обёртка для Picker segmented |
| `DateSectionHeader` | Заголовок группы по дате + сумма |
| `ExpenseIncomeProgressBar` | Двойной progress bar |
| `SkeletonView` | Loading placeholder анимация |
| `WarningMessageView` | Предупреждение/ошибка |
| `InfoRow` | Label + value row |
| `BrandLogoView` | Логотип бренда по имени |
| `SiriWaveView` | Анимация волны для voice |
| `HighlightedText` | Текст с entity highlights |

### Дублирование UI — зоны внимания
1. **Modal Edit Views** — `AccountEditView`, `CategoryEditView`, `DepositEditView`, `SubscriptionEditView` — похожая структура (form + toolbar save/cancel), могут частично share layout logic
2. **List Row Pattern** — `AccountRow`, `CategoryRow`, `SubcategoryRow` — идентичная структура icon + label + edit/delete
3. **RecognizedTextView** вложена в `ContentView.swift` (строка 599) — должна быть вынесена в отдельный файл

### Рекомендации
- Выделить `EditSheetLayout` компонент для modal-форм (NavigationView + toolbar save/cancel)
- Выделить `ManagementRow` компонент для list rows с edit/delete swipe

---

## 8. Дизайн-система

### Файл: `Utils/AppTheme.swift`

#### Spacing (4pt grid)
```swift
AppSpacing.xs  = 4   // micro (icon ↔ text)
AppSpacing.sm  = 8   // rows, button internals
AppSpacing.md  = 12  // default VStack/HStack, card padding
AppSpacing.lg  = 16  // screen horizontal padding, between cards
AppSpacing.xl  = 20  // between major sections
AppSpacing.xxl = 24  // between screen sections
AppSpacing.xxxl= 32  // screen margins (rare)
```

#### Corner Radius
```swift
AppRadius.sm     = 8   // chips, small buttons
AppRadius.md     = 10  // standard cards/buttons
AppRadius.lg     = 12  // large cards
AppRadius.pill   = 20  // pills, filter chips
AppRadius.circle = ∞   // avatars, category icons
```

#### Typography
```swift
AppTypography.h1          = largeTitle.bold
AppTypography.h2          = title.semibold
AppTypography.h3          = title2.semibold  // card headers
AppTypography.h4          = title3.semibold  // row titles
AppTypography.bodyLarge   = body.medium      // amounts
AppTypography.body        = body             // default
AppTypography.bodySmall   = subheadline      // secondary
AppTypography.caption     = caption
AppTypography.captionEmphasis = caption.medium
AppTypography.caption2    = caption2
```

#### Icon Sizes
```swift
AppIconSize.sm    = 16  // inline
AppIconSize.md    = 20  // toolbar
AppIconSize.lg    = 24  // emphasized
AppIconSize.xl    = 32  // bank logos
AppIconSize.xxl   = 44  // category circles
AppIconSize.xxxl  = 48  // hero/empty state
AppIconSize.fab   = 56  // floating action
AppIconSize.coin  = 64  // category coins
```

#### Semantic Colors (`AppColors`)
```swift
AppColors.cardBackground      = systemGray6
AppColors.secondaryBackground = systemGray5
AppColors.screenBackground    = systemBackground
// Semantic: income=.green, expense=.red, transfer=.blue
```

#### View Modifiers
```swift
.cardStyle(radius:padding:)      // standard card
.rowStyle()                      // list row padding
.chipStyle(isSelected:)          // filter chip
.filterChipStyle(isSelected:)    // standardized filter
.glassCardStyle(radius:)         // glass morphism effect ← PRIMARY CARD STYLE
.fallbackIconStyle(size:)        // placeholder icon
.screenPadding()                 // horizontal lg padding
.sectionSpacing()                // vertical md padding
```

#### Animation
```swift
AppAnimation.fast     = 0.1s
AppAnimation.standard = 0.25s
AppAnimation.slow     = 0.35s
AppAnimation.spring   = Spring(response: 0.3, damping: 0.6)
```

#### Button Style
```swift
.buttonStyle(.bounce)  // BounceButtonStyle — scale + brightness on press
```

### Правила для новых экранов
1. **ВСЕГДА** используйте `AppSpacing`, `AppRadius`, `AppTypography`, `AppIconSize`
2. **НИКОГДА** не хардкодите числа для spacing/padding/radius
3. Карточки: `.glassCardStyle()` как основной стиль
4. Фильтры: `.filterChipStyle(isSelected:)`
5. Кнопки навигации: `.buttonStyle(.bounce)`
6. Цвета: используйте `.primary`, `.secondary` для текста; semantic colors для transaction types

---

## 9. Локализация

### Поддержка
- **Английский** (`en.lproj/Localizable.strings`) — primary
- **Русский** (`ru.lproj/Localizable.strings`) — полная поддержка

### Формат ключей
Dot-notation с MARK-разделением:
```
navigation.home = "Home";
button.save = "Save";
emptyState.noTransactions = "No transactions";
error.validation.enterAmount = "Enter a valid amount";
```

### Как использовать
```swift
// Стандартный паттерн:
Text(String(localized: "button.save"))

// С defaultValue (для случаев когда ключ новый):
Text(String(localized: "progress.loadingData", defaultValue: "Loading data..."))
```

### Проблемы и долги
1. **Hardcoded strings** в `ContentView.swift` (строка 551): `"Не удалось извлечь текст из PDF..."` — русский текст вместо ключа локализации
2. **Inconsistency в naming:** часть ключей используют underscore (`budget_amount`), основная часть — dot-notation (`button.save`)
3. **Budget section** Keys не follow the dot-notation: `"budget_amount"`, `"budget_period"`, `"weekly"`, `"monthly"` — должны быть `"budget.amount"`, `"budget.period"`, `"budget.weekly"`
4. **Accessibility labels** в `AccountCard` — hardcoded English strings (строка 32 AccountCard.swift)

---

## 10. Расширяемость проекта

### Добавление новой фичи
1. Создать Service в `Services/` с бизнес-логикой
2. Создать или расширить ViewModel в `ViewModels/`
3. Если новый глобальный контекст — добавить в `AppCoordinator`
4. Зарегистрировать зависимости в `AppCoordinator.init()`
5. Создать Views в `Views/`, компоненты в `Views/Components/`
6. Добавить localization keys в оба `.strings` файла

### Добавление нового экрана
1. Файл в `Views/` (n.ex: `MyFeatureView.swift`)
2. Принимать ViewModels через init параметры (НЕ создавать внутри)
3. Navigation: добавить NavigationLink или `.sheet()` в родительский View
4. Использовать дизайн-токены из AppTheme

### Добавление нового компонента
1. Файл в `Views/Components/`
2. Все styling через AppTheme tokens
3. Компонент должен быть полностью reusable — принимать данные через init
4. Добавить `#Preview` для Xcode Canvas

### Добавление новой сущности
1. Модель в `Models/` (Codable struct)
2. CoreData entity (Class + Properties файлы) в `CoreData/Entities/`
3. Добавить load/save в `DataRepositoryProtocol`
4. Реализовать в `CoreDataRepository` + `UserDefaultsRepository`
5. Добавить в `DataMigrationService` (если нужна миграция)

### Слои, нельзя нарушать
- **View → ViewModel** (не View → Service напрямую)
- **ViewModel → Repository** через `DataRepositoryProtocol` (не прямой CoreData доступ)
- **Services** не знают про Views
- **Models** — чистые data structs без SwiftUI зависимостей

### Гибкие зоны
- Компоненты в `Components/` можно свободно добавлять
- Services — isolated, легко тестируются
- `DataRepositoryProtocol` позволяет подменять persistence backend

### Архитектурные ограничения
- `TransactionsViewModel` — central hub, все balance updates проходят через него
- `AppCoordinator` — единая точка инициализации, не может быть два AppCoordinator
- CoreData requires Main Actor или explicit background context — save operations должны учитывать thread safety

---

## 11. Технические долги и риски

### ✅ Исправлено (v2.0)

**2026-01-28:** Выполнен рефакторинг критических долгов:
- ✅ `fatalError` в CoreDataStack заменён на грейсфул дегрейдацию
- ✅ 492 debug `print()` удалены (оставлены только в `#if DEBUG`)
- ✅ Hardcoded Russian strings локализованы
- ✅ Budget localization keys унифицированы (dot-notation)
- ✅ Legacy duplicate handling удалён из CoreDataRepository
- ✅ `createdDate` добавлен в Account model
- ✅ AddTransactionModal вынесен в отдельный файл
- ✅ TransactionRow дубль устранён (параметризован DepositTransactionRow)
- ✅ EmptyStateView compact style добавлен
- ✅ **TransactionsViewModel декомпозирован:** 2205 → 2134 строк (-71)
  - Выделен `TransactionCacheManager` (77 строк)
  - Выделен `TransactionCurrencyService` (70 строк)

### Оставшиеся долги

| Файл | Проблема | Приоритет |
|------|----------|-----------|
| `CoreDataRepository.swift` (~1177 lines) | Очень большой, но допустимо (генерируемый паттерн CRUD) | Низкий |
| Navigation API | Использует `NavigationView` (iOS 15) вместо `NavigationStack` (iOS 16+) | Низкий |

### Дублирование UI
1. **Modal edit layouts** — 5 edit views с идентичной структурой (NavigationView + Form + toolbar) — можно выделить `EditSheetLayout`
2. **Management rows** — AccountRow, CategoryRow, SubcategoryRow — одинаковый layout — можно выделить `ManagementRow`

### ML Integration
- `CategoryMLPredictor` (строка 45) — TODO: реализовать предсказание когда модель будет обучена. Блокирован обученной моделью.

---

## 12. История изменений и рекомендации

### v2.0 (2026-01-28) — Рефакторинг долгов

**Выполнено:**
- P0: fatalError → грейсфул дегрейдация, hardcoded strings → локализация
- P1: 492 print() удалены, budget keys унифицированы, accessibility labels
- P2: createdDate в Account, AddTransactionModal extraction, EmptyStateView compact, TransactionRow уify
- P3: TransactionsViewModel декомпозирован → `TransactionCacheManager` + `TransactionCurrencyService`

### Оставшиеся рекомендации

**Низкий приоритет:**
1. **NavigationStack** (iOS 16+) — мигрировать с NavigationView если deployment target позволяет
2. **EditSheetLayout** — выделить shared component для modal edit forms
3. **ManagementRow** — выделить shared row component для management lists
4. **CoreDataRepository** — декомпозировать если файл растёт дальше 1500+ строк
5. **CategoryMLPredictor** — реализовать ML предсказание когда модель будет обучена

---

## Как использовать этот документ

### Передача другому AI
Передайте весь файл как "project context" prompt. Ключевые секции для конкретных задач:
- **Добавление фичи** → Секции 2, 3, 10
- **Работа с UI** → Секции 6, 7, 8
- **Работа с данными** → Секции 4, 5
- **Рефакторинг** → Секции 11, 12
- **Локализация** → Секция 9

### Типы задач, что можно решать
- Добавление новых экранов и компонентов (сверяться с дизайн-системой)
- Реализация бизнес-логики (сверяться со структурой сервисов)
- Рефакторинг (опираться на секцию 11 для приоритетов)
- Баг-фиксинг (использовать карту зависимостей из секции 2)
- Онбordinг новых разработчиков (секции 1-3 как стартовая точка)

### Как использовать как источник истины
- **Дизайн-система** — AppTheme.swift описан полностью в секции 8. Любой вопрос про spacing/colors/typography — смотрите туда.
- **Правильный паттерн для View** — секция 6 + примеры из существующих Views.
- **Где добавить новый код** — секция 3 (структура папок) + секция 10 (guide по добавлению).
- **Если не уверены** — сверяйтесь с AppCoordinator.swift и ContentView.swift как "backbone" приложения.
