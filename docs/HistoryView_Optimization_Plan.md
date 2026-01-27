# HistoryView Optimization Plan

## 🎯 Краткий План Оптимизации

### Приоритет 1: Критические Оптимизации (1-2 дня)

#### ✅ Task 1.1: Устранить дублирование кеша
**Проблема:** `cachedGroupedTransactions` и `cachedSortedKeys` дублируют данные из `paginationManager`

**Действия:**
```swift
// Удалить из HistoryView.swift:
@State private var cachedGroupedTransactions: [String: [Transaction]] = [:]
@State private var cachedSortedKeys: [String] = []

// Использовать напрямую:
let grouped = paginationManager.groupedTransactions
let sortedKeys = paginationManager.visibleSections
```

**Файлы:**
- `HistoryView.swift` (строки 23-25, 295-299)

**Выгода:** -15% памяти, устранение рассинхронизации

---

#### ✅ Task 1.2: Мемоизация day expenses
**Проблема:** Пересчет expenses при каждом рендере секции

**Действия:**
1. Создать `DateSectionExpensesCache.swift`
2. Реализовать кеширование:

```swift
@MainActor
class DateSectionExpensesCache: ObservableObject {
    private var cache: [String: Double] = [:]

    func getExpenses(
        for dateKey: String,
        transactions: [Transaction],
        baseCurrency: String,
        viewModel: TransactionsViewModel
    ) -> Double {
        if let cached = cache[dateKey] {
            return cached
        }

        let expenses = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { total, transaction in
                total + viewModel.getConvertedAmountOrCompute(
                    transaction: transaction,
                    to: baseCurrency
                )
            }

        cache[dateKey] = expenses
        return expenses
    }

    func invalidate() {
        cache.removeAll()
    }
}
```

3. Использовать в HistoryView:
```swift
@StateObject private var expensesCache = DateSectionExpensesCache()

private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
    let dayExpenses = expensesCache.getExpenses(
        for: dateKey,
        transactions: transactions,
        baseCurrency: baseCurrency,
        viewModel: transactionsViewModel
    )

    return DateSectionHeader(...)
}
```

**Файлы:**
- Новый: `Views/History/DateSectionExpensesCache.swift`
- Изменить: `HistoryView.swift` (строки 306-324)

**Выгода:** -70-90% вычислений при скролле

---

#### ✅ Task 1.3: Исправить локализацию дат
**Проблема:** ViewModel может использовать нелокализованные ключи

**Действия:**
1. Проверить `TransactionsViewModel.groupAndSortTransactionsByDate()`
2. Убедиться, что используется `String(localized: "date.today")`
3. Удалить TODO комментарий

**Файлы:**
- `HistoryView.swift` (строка 33)
- `TransactionsViewModel.swift`

**Выгода:** Устранение технического долга, корректная локализация

---

### Приоритет 2: Декомпозиция (2-3 дня)

#### ✅ Task 2.1: Создать HistoryFilterCoordinator
**Проблема:** View управляет слишком многими фильтрами

**Структура:**
```swift
@MainActor
class HistoryFilterCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedAccountFilter: String?
    @Published var searchText: String = ""
    @Published var debouncedSearchText: String = ""

    // MARK: - Private Properties
    private var searchTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?

    // MARK: - Public Methods
    func updateSearch(_ text: String) {
        searchText = text
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                debouncedSearchText = text
            }
        }
    }

    func updateAccountFilter(_ accountId: String?) {
        selectedAccountFilter = accountId
        filterTask?.cancel()

        filterTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Notify about filter change
            }
        }
    }

    func reset() {
        selectedAccountFilter = nil
        searchText = ""
        debouncedSearchText = ""
        searchTask?.cancel()
        filterTask?.cancel()
    }
}
```

**Использование в HistoryView:**
```swift
@StateObject private var filterCoordinator = HistoryFilterCoordinator()

// Заменить onChange на:
.onChange(of: filterCoordinator.debouncedSearchText) { _, _ in
    updateCachedTransactions()
}
```

**Файлы:**
- Новый: `ViewModels/HistoryFilterCoordinator.swift`
- Изменить: `HistoryView.swift` (строки 15-19, 117-148)

**Выгода:** SRP compliance, переиспользуемость, легкость тестирования

---

#### ✅ Task 2.2: Выделить HistoryScrollBehavior
**Проблема:** Сложная логика автоскролла (45 строк)

**Структура:**
```swift
struct HistoryScrollBehavior {
    static func findScrollTarget(
        sections: [String],
        grouped: [String: [Transaction]],
        todayKey: String,
        yesterdayKey: String,
        dateFormatter: DateFormatter
    ) -> String? {
        // Сначала проверяем "Сегодня"
        if sections.contains(todayKey) {
            return todayKey
        }

        // Затем "Вчера"
        if sections.contains(yesterdayKey) {
            return yesterdayKey
        }

        // Ищем первую прошлую секцию
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for key in sections {
            if key == todayKey || key == yesterdayKey {
                continue
            }

            if let transactions = grouped[key],
               let firstTransaction = transactions.first,
               let date = dateFormatter.date(from: firstTransaction.date) {
                let transactionDay = calendar.startOfDay(for: date)
                if transactionDay <= today {
                    return key
                }
            }
        }

        // Fallback
        return sections.first
    }
}
```

**Использование:**
```swift
.task {
    try? await Task.sleep(nanoseconds: 150_000_000)

    let scrollTarget = HistoryScrollBehavior.findScrollTarget(
        sections: paginationManager.visibleSections,
        grouped: paginationManager.groupedTransactions,
        todayKey: todayKey,
        yesterdayKey: yesterdayKey,
        dateFormatter: DateFormatters.dateFormatter
    )

    if let target = scrollTarget {
        withAnimation {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}
```

**Файлы:**
- Новый: `Views/History/HistoryScrollBehavior.swift`
- Изменить: `HistoryView.swift` (строки 231-277)

**Выгода:** Читаемость, тестируемость, изоляция логики

---

#### ✅ Task 2.3: Выделить HistoryTransactionsList
**Проблема:** Смешение логики списка и координации

**Структура:**
```swift
struct HistoryTransactionsList: View {
    @ObservedObject var paginationManager: TransactionPaginationManager
    let baseCurrency: String
    let customCategories: [String]
    let accounts: [Account]
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let onSectionAppear: (String) -> Void
    let scrollTargetFinder: () -> String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(paginationManager.visibleSections, id: \.self) { dateKey in
                    Section(header: dateHeader(for: dateKey)) {
                        ForEach(paginationManager.groupedTransactions[dateKey] ?? []) { transaction in
                            TransactionCard(
                                transaction: transaction,
                                currency: baseCurrency,
                                customCategories: customCategories,
                                accounts: accounts,
                                viewModel: transactionsViewModel,
                                categoriesViewModel: categoriesViewModel
                            )
                        }
                    }
                    .id(dateKey)
                    .onAppear {
                        if paginationManager.shouldLoadMore(for: dateKey) {
                            paginationManager.loadNextPage()
                        }
                        onSectionAppear(dateKey)
                    }
                }

                if paginationManager.isLoadingMore {
                    loadingSection
                }
            }
            .listStyle(PlainListStyle())
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)

                if let target = scrollTargetFinder() {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
    }

    private func dateHeader(for dateKey: String) -> some View {
        // Header logic
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView().padding()
                Spacer()
            }
        }
    }
}
```

**Файлы:**
- Новый: `Views/History/HistoryTransactionsList.swift`
- Изменить: `HistoryView.swift` (строки 165-280)

**Выгода:** Изоляция UI, переиспользуемость, упрощение HistoryView

---

### Приоритет 3: Performance & Polish (1-2 дня)

#### ✅ Task 3.1: Добавить анимации
**Действия:**
```swift
// В HistoryFilterSection:
.onChange(of: selectedAccountFilter) { _, _ in
    withAnimation(AppAnimation.standard) {
        HapticManager.selection()
    }
}

// В HistoryTransactionsList:
ForEach(sections, id: \.self) { section in
    Section(...)
        .transition(.opacity.animation(AppAnimation.standard))
}
```

**Файлы:**
- `HistoryView.swift`
- `HistoryFilterSection.swift`

**Выгода:** Более плавный UX

---

#### ✅ Task 3.2: Accessibility
**Действия:**
```swift
// Search bar:
.searchable(...)
    .accessibilityLabel("Search transactions")
    .accessibilityHint("Search by amount, category, or description")

// Filter chips:
FilterChip(...)
    .accessibilityLabel("Time filter: \(timeFilterManager.currentFilter.displayName)")
    .accessibilityHint("Double tap to change time period")

// Transaction list:
List {
    ...
}
.accessibilityLabel("Transaction history")
.accessibilityHint("Scroll to view more transactions")
```

**Файлы:**
- `HistoryView.swift`
- `HistoryFilterSection.swift`

**Выгода:** Поддержка VoiceOver, лучшая инклюзивность

---

#### ✅ Task 3.3: Performance тестирование
**Действия:**
1. Создать тестовый датасет с 1000+ транзакциями
2. Запустить Instruments (Time Profiler)
3. Измерить:
   - Время загрузки view
   - Время рендеринга секции
   - Scroll performance (FPS)
   - Время применения фильтров
4. Оптимизировать узкие места

**Целевые метрики:**
- Загрузка view: < 100ms
- Рендеринг секции: < 1ms
- Scroll: 60 FPS
- Применение фильтра: < 200ms

**Выгода:** Подтверждение оптимизаций, выявление новых узких мест

---

## 📋 Чеклист Реализации

### Phase 1 (Critical)
- [ ] Task 1.1: Удалить дублирование кеша
- [ ] Task 1.2: Реализовать DateSectionExpensesCache
- [ ] Task 1.3: Исправить локализацию дат
- [ ] Провести code review Phase 1
- [ ] Unit-тесты для DateSectionExpensesCache

### Phase 2 (Decomposition)
- [ ] Task 2.1: Создать HistoryFilterCoordinator
- [ ] Task 2.2: Выделить HistoryScrollBehavior
- [ ] Task 2.3: Выделить HistoryTransactionsList
- [ ] Провести code review Phase 2
- [ ] Unit-тесты для новых компонентов
- [ ] Обновить documentation

### Phase 3 (Polish)
- [ ] Task 3.1: Добавить анимации
- [ ] Task 3.2: Accessibility improvements
- [ ] Task 3.3: Performance тестирование
- [ ] Провести final code review
- [ ] Manual testing на реальных данных

---

## 🎯 Ожидаемые Результаты

| Метрика | До | После |
|---------|-----|-------|
| Строк в HistoryView | 370 | ~150 |
| @State переменных | 8 | 3-4 |
| Время рендеринга секции | ~3ms | ~0.5ms |
| Использование памяти | Базовая + 15% | Базовая |
| Unit-тестов | 0 | 10+ |
| SRP compliance | ❌ | ✅ |

---

## 🚀 Быстрый Старт

### Шаг 1: Создать ветку
```bash
git checkout -b feature/history-view-optimization
```

### Шаг 2: Начать с Phase 1
```bash
# Создать новый файл
touch AIFinanceManager/Views/History/DateSectionExpensesCache.swift

# Открыть в Xcode и начать реализацию
```

### Шаг 3: После каждой задачи
- Запустить тесты
- Проверить UI на разных устройствах
- Commit с описательным сообщением

### Шаг 4: После каждой фазы
- Code review
- Merge в main
- Обновить documentation

---

## 📚 Связанные Документы

- [Детальный анализ HistoryView](./HistoryView_Analysis_Report.md)
- [Design System Guide](../AIFinanceManager/Utils/AppTheme.swift)
- [TransactionsViewModel Optimization Plan](./TransactionsViewModel_Optimization_Plan.md)

---

**Последнее обновление:** 2026-01-27
**Следующий review:** После завершения Phase 1
