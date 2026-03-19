# План исправления: Фильтр времени → Обновление сумм категорий

**Дата:** 2026-02-01
**Статус:** 🎯 Ready for Implementation
**Приоритет:** P0 Critical
**Оценка:** 1.5 часа

---

## Проблема

При изменении фильтра по времени на главной странице:
- ❌ Суммы у категорий расходов НЕ обновляются
- ✅ После перезапуска приложения суммы корректны

**Root Cause:** `TransactionCacheManager.cachedCategoryExpenses` не учитывает `TimeFilter` как часть cache key.

**Полный анализ:** См. `Docs/TIME_FILTER_CATEGORY_TOTALS_ANALYSIS.md`

---

## Решение: Cache Key с TimeFilter

Кэшировать результаты `categoryExpenses` отдельно для каждого фильтра времени.

**Преимущества:**
- ✅ Суммы обновляются мгновенно при изменении фильтра
- ✅ Переключение между фильтрами использует кэш (быстрее)
- ✅ Минимальные изменения (3 файла)
- ✅ Убирает временный workaround

---

## Изменения

### Phase 1: TransactionCacheManager.swift ✨

**Файл:** `AIFinanceManager/Services/TransactionCacheManager.swift`

**Что меняем:**

```swift
// ДО (lines ~26-27):
var cachedCategoryExpenses: [String: CategoryExpense]?
var categoryExpensesCacheInvalidated = true

// ПОСЛЕ:
private var categoryExpensesCache: [String: [String: CategoryExpense]] = [:]
private var cacheAccessOrder: [String] = []
private let maxCacheSize = 10
```

**Новые методы:**

```swift
// MARK: - Category Expenses Cache (per-filter)

/// Get cached category expenses for specific time filter
func getCachedCategoryExpenses(for filter: TimeFilter) -> [String: CategoryExpense]? {
    let key = makeCacheKey(filter)

    // Update access order for LRU
    if let index = cacheAccessOrder.firstIndex(of: key) {
        cacheAccessOrder.remove(at: index)
        cacheAccessOrder.append(key)
    }

    return categoryExpensesCache[key]
}

/// Set cached category expenses for specific time filter
func setCachedCategoryExpenses(_ expenses: [String: CategoryExpense], for filter: TimeFilter) {
    let key = makeCacheKey(filter)

    // Remove old entry if exists
    if let index = cacheAccessOrder.firstIndex(of: key) {
        cacheAccessOrder.remove(at: index)
    }

    // Add to end (most recent)
    cacheAccessOrder.append(key)
    categoryExpensesCache[key] = expenses

    // Evict oldest if over limit
    if cacheAccessOrder.count > maxCacheSize {
        let oldestKey = cacheAccessOrder.removeFirst()
        categoryExpensesCache.removeValue(forKey: oldestKey)
    }
}

/// Invalidate all category expenses caches
func invalidateCategoryExpenses() {
    categoryExpensesCache.removeAll()
    cacheAccessOrder.removeAll()
}

/// Generate unique cache key for time filter
private func makeCacheKey(_ filter: TimeFilter) -> String {
    let range = filter.dateRange()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

    let start = formatter.string(from: range.start)
    let end = formatter.string(from: range.end)

    return "\(filter.preset.rawValue)_\(start)_\(end)"
}
```

**Обновить `invalidateAll()`:**

```swift
/// Invalidate all caches at once
func invalidateAll() {
    summaryCacheInvalidated = true
    invalidateCategoryExpenses()  // ← Изменение здесь
    categoryListsCacheInvalidated = true
    balanceCacheInvalidated = true
    accountsCacheInvalidated = true
    subcategoryIndexInvalidated = true
    parsedDatesCache.removeAll(keepingCapacity: true)
    indexManager.invalidate()
}
```

**Время:** 30 минут

---

### Phase 2: TransactionQueryService.swift ✨

**Файл:** `AIFinanceManager/Services/Transactions/TransactionQueryService.swift`

**Метод `getCategoryExpenses()` (lines 93-120):**

```swift
// ДО:
func getCategoryExpenses(
    timeFilter: TimeFilter,
    baseCurrency: String,
    validCategoryNames: Set<String>?,
    aggregateCache: CategoryAggregateCache,
    cacheManager: TransactionCacheManager
) -> [String: CategoryExpense] {

    // Check cache
    if !cacheManager.categoryExpensesCacheInvalidated,
       let cached = cacheManager.cachedCategoryExpenses {
        return cached
    }

    // Use aggregate cache for efficient calculation
    let result = aggregateCache.getCategoryExpenses(
        timeFilter: timeFilter,
        baseCurrency: baseCurrency,
        validCategoryNames: validCategoryNames
    )

    cacheManager.cachedCategoryExpenses = result
    cacheManager.categoryExpensesCacheInvalidated = false

    return result
}

// ПОСЛЕ:
func getCategoryExpenses(
    timeFilter: TimeFilter,
    baseCurrency: String,
    validCategoryNames: Set<String>?,
    aggregateCache: CategoryAggregateCache,
    cacheManager: TransactionCacheManager
) -> [String: CategoryExpense] {

    // ✅ Check cache with time filter as key
    if let cached = cacheManager.getCachedCategoryExpenses(for: timeFilter) {
        return cached
    }

    // Use aggregate cache for efficient calculation
    let result = aggregateCache.getCategoryExpenses(
        timeFilter: timeFilter,
        baseCurrency: baseCurrency,
        validCategoryNames: validCategoryNames
    )

    // ✅ Save to cache with time filter as key
    cacheManager.setCachedCategoryExpenses(result, for: timeFilter)

    return result
}
```

**Время:** 15 минут

---

### Phase 3: TransactionsViewModel.swift 🧹

**Файл:** `AIFinanceManager/ViewModels/TransactionsViewModel.swift`

**Метод `categoryExpenses()` (lines 355-380):**

```swift
// ДО:
func categoryExpenses(
    timeFilterManager: TimeFilterManager,
    categoriesViewModel: CategoriesViewModel? = nil
) -> [String: CategoryExpense] {
    let validCategoryNames: Set<String>? = categoriesViewModel.map { vm in
        Set(vm.customCategories.map { $0.name })
    }

    // IMPORTANT: Temporarily invalidate category expenses cache to force recalculation
    // The cache doesn't account for time filters, so we need fresh calculation
    let wasInvalidated = cacheManager.categoryExpensesCacheInvalidated
    cacheManager.categoryExpensesCacheInvalidated = true

    let result = queryService.getCategoryExpenses(
        timeFilter: timeFilterManager.currentFilter,
        baseCurrency: appSettings.baseCurrency,
        validCategoryNames: validCategoryNames,
        aggregateCache: aggregateCache,
        cacheManager: cacheManager
    )

    // Restore invalidation state to allow caching for non-filtered queries
    cacheManager.categoryExpensesCacheInvalidated = wasInvalidated

    return result
}

// ПОСЛЕ:
func categoryExpenses(
    timeFilterManager: TimeFilterManager,
    categoriesViewModel: CategoriesViewModel? = nil
) -> [String: CategoryExpense] {
    let validCategoryNames: Set<String>? = categoriesViewModel.map { vm in
        Set(vm.customCategories.map { $0.name })
    }

    // ✅ Workaround removed - cache now handles time filters correctly
    return queryService.getCategoryExpenses(
        timeFilter: timeFilterManager.currentFilter,
        baseCurrency: appSettings.baseCurrency,
        validCategoryNames: validCategoryNames,
        aggregateCache: aggregateCache,
        cacheManager: cacheManager
    )
}
```

**Время:** 10 минут

---

## Тестирование 🧪

**Сценарии проверки:**

### 1. Базовая функциональность
- [ ] Открыть приложение с фильтром "All Time"
- [ ] Проверить суммы категорий (например, Food: 5000₸)
- [ ] Изменить фильтр на "This Month"
- [ ] **Ожидается:** Суммы обновляются БЕЗ перезапуска
- [ ] Изменить фильтр обратно на "All Time"
- [ ] **Ожидается:** Суммы возвращаются к исходным (из кэша, быстро)

### 2. Кэш работает корректно
- [ ] Переключаться между "This Month" ↔ "Last Month" несколько раз
- [ ] **Ожидается:** Мгновенное переключение (кэш используется)
- [ ] Проверить в консоли отсутствие пересчётов для кэшированных фильтров

### 3. Инвалидация кэша
- [ ] Выбрать фильтр "This Month"
- [ ] Запомнить сумму категории (например, Food: 1500₸)
- [ ] Добавить новую транзакцию в категорию Food на 500₸
- [ ] **Ожидается:** Сумма обновилась до 2000₸
- [ ] Переключить фильтр на "Last Month" и обратно
- [ ] **Ожидается:** Сумма остаётся 2000₸ (кэш инвалидирован и пересчитан)

### 4. Edge cases
- [ ] Попробовать Custom filter (выбрать произвольный диапазон дат)
- [ ] **Ожидается:** Суммы корректны для выбранного диапазона
- [ ] Переключиться на предустановленный фильтр (Today, This Week)
- [ ] **Ожидается:** Суммы корректны

### 5. Производительность
- [ ] Открыть Performance Profiler (если доступен)
- [ ] Переключить фильтр первый раз: **Ожидается ~50ms**
- [ ] Переключить обратно (из кэша): **Ожидается <5ms**

**Время:** 20 минут

---

## Rollback Plan

Если что-то пойдёт не так:

1. **Git revert** последних коммитов
2. Альтернатива: **Вариант 2** из анализа - отключить кэш полностью:

```swift
// TransactionQueryService.swift:getCategoryExpenses()
// Просто убрать проверку кэша - всегда пересчитывать
let result = aggregateCache.getCategoryExpenses(
    timeFilter: timeFilter,
    baseCurrency: baseCurrency,
    validCategoryNames: validCategoryNames
)
return result  // Не кэшируем
```

---

## Checklist

- [ ] Phase 1: Обновить TransactionCacheManager.swift
- [ ] Phase 2: Обновить TransactionQueryService.swift
- [ ] Phase 3: Очистить TransactionsViewModel.swift
- [ ] Запустить Build - проверить отсутствие ошибок
- [ ] Тестирование: Сценарий 1 (базовая функциональность)
- [ ] Тестирование: Сценарий 2 (кэш работает)
- [ ] Тестирование: Сценарий 3 (инвалидация кэша)
- [ ] Тестирование: Сценарий 4 (edge cases)
- [ ] Тестирование: Сценарий 5 (производительность)
- [ ] Commit changes
- [ ] Обновить PROJECT_BIBLE.md (упомянуть исправление)

---

## Дополнительные улучшения (опционально)

### Memory Warning Handling

Добавить очистку кэша при нехватке памяти:

```swift
// TransactionCacheManager.swift

init() {
    // Listen for memory warnings
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleMemoryWarning),
        name: UIApplication.didReceiveMemoryWarningNotification,
        object: nil
    )
}

@objc private func handleMemoryWarning() {
    // Clear category expenses cache but keep most recent
    if cacheAccessOrder.count > 2 {
        let keepRecent = 2
        let removeCount = cacheAccessOrder.count - keepRecent
        for _ in 0..<removeCount {
            let oldestKey = cacheAccessOrder.removeFirst()
            categoryExpensesCache.removeValue(forKey: oldestKey)
        }
    }
}
```

### Logging для мониторинга

```swift
// TransactionCacheManager.swift

func getCachedCategoryExpenses(for filter: TimeFilter) -> [String: CategoryExpense]? {
    let key = makeCacheKey(filter)

    if let cached = categoryExpensesCache[key] {
        #if DEBUG
        print("✅ CategoryExpenses cache HIT for filter: \(filter.displayName)")
        #endif

        // Update access order
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
            cacheAccessOrder.append(key)
        }

        return cached
    } else {
        #if DEBUG
        print("❌ CategoryExpenses cache MISS for filter: \(filter.displayName)")
        #endif
        return nil
    }
}
```

---

**Статус:** Ready to Implement
**Начать с:** Phase 1 (TransactionCacheManager.swift)
