# Insights Metrics Reference

**Last Updated:** 2026-02-23
**Phase coverage:** Phase 17–27 (all metrics)

## Легенда

| Символ | Значение |
|--------|----------|
| ✅ | Полностью подчиняется выбранной гранулярности; бакет-сравнение через `currentPeriodKey/previousPeriodKey` |
| ⚠️ | Значение текущее (non-windowed), только trend arrow следует гранулярности |
| 🔒 | Фиксированный lookback (3 мес, 6 мес, 5 лет — по дизайну) |
| ❌ | Не зависит от времени (текущее состояние или all-time) |

Гранулярность применяется через `InsightGranularity.dateRange(firstTransactionDate:)`:
- `.week` → последние 52 недели (rolling)
- `.month / .quarter / .year / .allTime` → от первой транзакции до сегодня (все данные)

---

## SPENDING

### `topSpendingCategory`
- **Что считает:** категория расходов с наибольшей суммой за **текущий** период гранулярности
- **Данные:** `currentBucketPoint` — текущий бакет из `periodPoints` (Phase 31); при отсутствии — fallback на `windowedTransactions`
- **Детализация:** `categoryBreakdown` — топ-5 категорий с подкатегориями
- **Fast path:** `CategoryAggregateService.fetchRange(from: cp.periodStart, to: cp.periodEnd)` → O(M) вместо O(N)
- **Гранулярность:** ✅ — данные скоупированы по **текущему бакету** (не по всему окну)

### `monthOverMonthChange`
- **Что считает:** расходы текущего бакета гранулярности vs предыдущего
- **Данные (Phase 30, основной путь):** `periodPoints` — `currentPeriodKey` vs `previousPeriodKey`; title и comparisonPeriod берутся из `granularity.monthOverMonthTitle / comparisonPeriodName`
- **Fallback (legacy path):** `allTransactions` O(N) scan по calendar-месяцам — используется только если `periodPoints` пустые или `granularity == .allTime`
- **Пропускается для `.allTime`:** `previousPeriodKey == currentPeriodKey` → осмысленного сравнения нет
- **Гранулярность:** ✅ для `.week/.month/.quarter/.year`; не генерируется для `.allTime`

### `averageDailySpending`
- **Что считает:** суммарные расходы за период ÷ количество дней
- **Данные:** `periodSummary` (рассчитан из `windowedTransactions`)
- **Дни:** `calendar.dateComponents([.day], from: windowStart, to: min(windowEnd, today)).day`
- **Гранулярность:** ✅ — для `.week` = 364 дня, для `.month` = все дни с первой транзакции

### `spendingSpike` *(Phase 24)*
- **Что считает:** категория, у которой расходы в текущем месяце > 1.5× среднего за 3 мес
- **Данные:** `CategoryAggregateService` — фиксированный lookback 3 мес
- **Порог:** multiplier ≥ 1.5×; severity Critical если > 2×
- **Гранулярность:** 🔒

### `categoryTrend` *(Phase 24)*
- **Что считает:** категория, у которой расходы растут 2+ месяцев подряд
- **Данные:** `CategoryAggregateService` — фиксированный lookback 6 мес
- **Streak:** минимум 2 месяца роста, минимум 3 записи по категории
- **Гранулярность:** 🔒

---

## INCOME

### `incomeGrowth`
- **Что считает:** изменение доходов текущего бакета гранулярности vs предыдущего
- **Данные (Phase 30, основной путь):** `periodPoints` — `currentPeriodKey` vs `previousPeriodKey` (analogично `monthOverMonthChange`, но по `.income`)
- **Fallback (legacy path):** `allTransactions` O(N) scan по calendar-месяцам — только при пустых `periodPoints` или `.allTime`
- **Пропускается для `.allTime`:** аналогично `monthOverMonthChange`
- **Гранулярность:** ✅ для `.week/.month/.quarter/.year`; не генерируется для `.allTime`

### `incomeVsExpenseRatio`
- **Что считает:** `income / (income + expenses) × 100` — доля дохода в общем потоке
- **Данные:** `periodSummary` (из `windowedTransactions`)
- **Severity:** Positive ≥1.5×, Neutral ≥1.0×, Critical <1.0× (тратим больше дохода)
- **Гранулярность:** ✅

### `incomeSourceBreakdown` *(Phase 24, Phase 31)*
- **Что считает:** группировка доходных транзакций по категории за **текущий бакет** гранулярности
- **Данные (Phase 31):** `currentBucketForForecasting` — `filterByTimeRange(allTransactions, start: cp.periodStart, end: cp.periodEnd)` для текущего бакета; fallback на `windowedTransactions`
- **Условия:** ≥2 категории дохода, totalIncome > 0
- **Гранулярность:** ✅ — скоупирован по текущему периоду (до Phase 31 был ❌ all-time)

---

## BUDGET

### `budgetOverspend`
- **Что считает:** количество категорий, превысивших бюджет в текущем периоде
- **Данные:** `windowedTransactions` → `budgetService.budgetProgress()`
- **Fast path:** `BudgetSpendingCacheService` — O(1) cached spent per category
- **Детализация:** `budgetProgressList`, sorted by % utilization desc
- **Гранулярность:** ✅

### `budgetUnderutilized`
- **Что считает:** категории, использовавшие < 80% бюджета (позитивный инсайт)
- **Данные:** то же, что `budgetOverspend`
- **Условие:** `0 < percentage < 80`
- **Гранулярность:** ✅

### `projectedOverspend`
- **Что считает:** категории, которые превысят бюджет если темп расходов сохранится
- **Формула:** `projected = (spent / daysElapsed) × totalDaysInBudgetPeriod`
- **Данные:** `windowedTransactions` + текущий день месяца
- **Гранулярность:** ✅

---

## RECURRING

### `totalRecurringCost`
- **Что считает:** суммарный месячный эквивалент всех активных recurring series в baseCurrency
- **Конвертация:** Daily×30, Weekly×4.33, Monthly×1, Yearly÷12
- **Данные:** `transactionStore.recurringSeries` (только active) — не зависит от транзакций
- **Детализация:** `recurringList`, sorted by monthlyEquivalent desc
- **Гранулярность:** ❌ — текущее состояние

### `subscriptionGrowth` *(Phase 24)*
- **Что считает:** рост суммы подписок — текущий total vs total 3 мес назад
- **Данные:** `transactionStore.recurringSeries`, filtered by `startDate < 3_months_ago`
- **Порог:** показывается только если |changePercent| > 5%
- **Гранулярность:** 🔒 — фиксированный lookback 3 мес

### `duplicateSubscriptions` *(Phase 24)*
- **Что считает:** активные подписки с одинаковой категорией ИЛИ похожей стоимостью (±15%)
- **Данные:** `transactionStore.recurringSeries` (kind == .subscription, active)
- **Гранулярность:** ❌ — текущее состояние

---

## CASHFLOW

### `netCashFlow`
- **Что считает:** net flow последнего периода (income − expenses) относительно среднего
- **Данные:** `computePeriodDataPoints(allTransactions, granularity:)` — бакеты по гранулярности
- **Fast path:** `MonthlyAggregateService.fetchLast(M)` → O(M) вместо O(N×M)
- **Детализация:** `periodTrend` — 6–12 периодов
- **Гранулярность:** ✅ — бакеты: неделя/месяц/квартал/год

### `bestMonth`
- **Что считает:** период с наибольшим net flow среди всех периодов в окне
- **Данные:** `periodPoints` (те же, что для `netCashFlow`)
- **Гранулярность:** ✅

### `worstMonth` *(Phase 24)*
- **Что считает:** период с наименьшим (отрицательным) net flow
- **Условия:** min netFlow < 0; не совпадает с bestMonth
- **Гранулярность:** ✅

### `projectedBalance`
- **Что считает:** текущий баланс + месячный нетто recurring (impact подписок)
- **Данные:** `transactionStore.accounts` (current balances) + `recurringSeries` (active)
- **Гранулярность:** ❌ — текущее состояние

---

## WEALTH

### `totalWealth`
- **Что считает:** сумма балансов всех счётов (текущее состояние капитала)
- **Данные:** `balanceFor()` callback per account
- **Детализация:** `wealthBreakdown` — список счётов с балансами
- **Тренд:** сравнивает net flow текущего периода vs предыдущего через `granularity.currentPeriodKey / previousPeriodKey`
- **Гранулярность:** ⚠️ — баланс текущий ❌; trend arrow — window-aware ✅

### `wealthGrowth` *(Phase 24)*
- **Что считает:** изменение богатства период к периоду (по бакетам гранулярности)
- **Данные:** `periodPoints` — кумулятивный баланс по периодам
- **Условие:** |changePercent| > 1%
- **Детализация:** `periodTrend` — кумулятивные точки баланса
- **Гранулярность:** ✅

### `accountDormancy` *(Phase 24)*
- **Что считает:** счета с положительным балансом, без активности 30+ дней
- **Данные:** `allTransactions` — O(A×N) scan для поиска последней даты по каждому счёту
- **Гранулярность:** ❌ — всегда 30 дней от сегодня

---

## SAVINGS *(Phase 24)*

### `savingsRate`
- **Что считает:** `(income − expenses) / income × 100` — % сбережений
- **Данные:** `windowedIncome`, `windowedExpenses` (window-scoped суммы от `generateAllInsights`)
- **Severity:** Positive >20%, Warning ≥10%, Critical <10%
- **Гранулярность:** ✅

### `emergencyFund`
- **Что считает:** `totalBalance / avgMonthlyExpenses` — сколько месяцев можно прожить без дохода
- **Данные:** `balanceFor()` + `MonthlyAggregateService.fetchLast(3)`
- **Severity:** Positive ≥3 мес, Warning ≥1 мес, Critical <1 мес
- **Гранулярность:** 🔒 — lookback 3 мес

### `savingsMomentum`
- **Что считает:** норма сбережений текущего месяца vs среднее за 3 предыдущих
- **Данные:** `MonthlyAggregateService.fetchLast(4)`
- **Порог:** показывается только если |delta| > 1%
- **Гранулярность:** 🔒 — lookback 4 мес

---

## FORECASTING *(Phase 24)*

### `spendingForecast`
- **Что считает:** `spentSoFar + (avgDaily30 × daysRemaining) + pendingRecurring` — прогноз расходов до конца месяца
- **Данные:** `MonthlyAggregateService.fetchLast(1)` + `CategoryAggregateService(last 30 days)` + active recurring
- **Гранулярность:** 🔒 — текущий месяц + последние 30 дней

### `balanceRunway`
- **Что считает:** `currentBalance / |avgMonthlyNetFlow|` — через сколько месяцев закончатся деньги
- **Данные:** `balanceFor()` + `MonthlyAggregateService.fetchLast(3)`
- **Особый случай:** если avgMonthlyNetFlow > 0 — показывает сумму сбережений вместо runway
- **Severity:** Positive ≥3 мес, Warning ≥1 мес, Critical <1 мес
- **Гранулярность:** 🔒 — lookback 3 мес

### `yearOverYear`
- **Что считает:** расходы этого месяца vs тот же месяц год назад
- **Данные:** `MonthlyAggregateService` — 2 конкретные точки: current month + same month −12 мес
- **Порог:** показывается только если |delta| > 3%
- **Severity:** Positive ≤−10%, Warning ≥+15%, Neutral otherwise
- **Гранулярность:** 🔒 — конкретные calendar-даты

### `incomeSeasonality`
- **Что считает:** какой calendar-месяц исторически приносит наибольший доход (за 5 лет)
- **Данные:** `MonthlyAggregateService.fetchRange(5 years back → now)` — группировка по номеру месяца (1–12)
- **Порог:** пиковый месяц > 10% выше среднего; ≥12 месяцев данных; ≥6 разных calendar-месяцев
- **Гранулярность:** 🔒 — lookback 5 лет

### `spendingVelocity`
- **Что считает:** текущий дневной темп расходов относительно прошлого месяца
- **Формула:** `(spentSoFar / dayOfMonth) / (lastMonthTotal / lastMonthDays)`
- **Данные:** `MonthlyAggregateService.fetchLast(2)`
- **Порог:** |ratio − 1.0| > 0.1 (только если >10% разница); dayOfMonth > 3
- **Гранулярность:** 🔒 — lookback 2 мес

---

## Сводная таблица

| Метрика | Категория | Гранулярность | Источник данных |
|---------|-----------|:---:|---|
| `topSpendingCategory` | spending | ✅ current bucket | CategoryAggregateService (current bucket) / O(N) fallback |
| `monthOverMonthChange` | spending | ✅ (skip allTime) | periodPoints currentPeriodKey/previousPeriodKey |
| `averageDailySpending` | spending | ✅ | periodSummary (windowed) |
| `spendingSpike` | spending | 🔒 3mo | CategoryAggregateService |
| `categoryTrend` | spending | 🔒 6mo | CategoryAggregateService |
| `incomeGrowth` | income | ✅ (skip allTime) | periodPoints currentPeriodKey/previousPeriodKey |
| `incomeVsExpenseRatio` | income | ✅ | periodSummary (windowed) |
| `incomeSourceBreakdown` | income | ✅ current bucket | filteredTransactions (current bucket) |
| `budgetOverspend` | budget | ✅ | BudgetSpendingCacheService O(1) |
| `budgetUnderutilized` | budget | ✅ | BudgetSpendingCacheService O(1) |
| `projectedOverspend` | budget | ✅ | windowedTransactions + day calc |
| `totalRecurringCost` | recurring | ❌ current | recurringSeries (active) |
| `subscriptionGrowth` | recurring | 🔒 3mo | recurringSeries by startDate |
| `duplicateSubscriptions` | recurring | ❌ current | recurringSeries (active subscriptions) |
| `netCashFlow` | cashFlow | ✅ | MonthlyAggregateService (fast) / O(N×M) fallback |
| `bestMonth` | cashFlow | ✅ | periodPoints |
| `worstMonth` | cashFlow | ✅ | periodPoints |
| `projectedBalance` | cashFlow | ❌ current | accounts + recurringSeries |
| `totalWealth` | wealth | ⚠️ | balanceFor() + periodPoints |
| `wealthGrowth` | wealth | ✅ | periodPoints (cumulative) |
| `accountDormancy` | wealth | ❌ 30d | allTransactions O(A×N) |
| `savingsRate` | savings | ✅ | windowedIncome / windowedExpenses |
| `emergencyFund` | savings | 🔒 3mo | balanceFor() + MonthlyAggregateService |
| `savingsMomentum` | savings | 🔒 4mo | MonthlyAggregateService |
| `spendingForecast` | forecasting | 🔒 30d | CategoryAggregateService + MonthlyAggregateService |
| `balanceRunway` | forecasting | 🔒 3mo | balanceFor() + MonthlyAggregateService |
| `yearOverYear` | forecasting | 🔒 calendar | MonthlyAggregateService (2 точки) |
| `incomeSeasonality` | forecasting | 🔒 5yr | MonthlyAggregateService |
| `spendingVelocity` | forecasting | 🔒 2mo | MonthlyAggregateService |

---

## Итоговые группы

### ✅ Полностью следуют гранулярности (15 метрик)
`topSpendingCategory` (current bucket), `monthOverMonthChange` (skip allTime), `averageDailySpending`, `incomeGrowth` (skip allTime), `incomeVsExpenseRatio`, `incomeSourceBreakdown` (current bucket), `budgetOverspend`, `budgetUnderutilized`, `projectedOverspend`, `netCashFlow`, `bestMonth`, `worstMonth`, `wealthGrowth`, `savingsRate`

### ⚠️ Значение текущее, trend arrow window-aware (1 метрика)
`totalWealth` — баланс счетов всегда текущий; trend направление вычисляется из `currentPeriodKey vs previousPeriodKey`

### 🔒 Фиксированный lookback по дизайну (10 метрик)
`spendingSpike` (3mo), `categoryTrend` (6mo), `subscriptionGrowth` (3mo), `emergencyFund` (3mo), `savingsMomentum` (4mo), `spendingForecast` (30d+current month), `balanceRunway` (3mo), `yearOverYear` (calendar), `incomeSeasonality` (5yr), `spendingVelocity` (2mo)

### ❌ Не привязаны ко времени — текущее состояние (4 метрики)
`totalRecurringCost`, `duplicateSubscriptions`, `projectedBalance`, `accountDormancy` (30 дней от сегодня)

---

## Архитектурные детали

### Period-over-period сравнения (Phase 30)
`monthOverMonthChange` и `incomeGrowth` используют **двухпутевую** логику:

**Основной путь (granularity + periodPoints):**
```swift
if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
    let thisTotal = periodPoints.first { $0.key == gran.currentPeriodKey }?.expenses ?? 0
    let prevTotal = periodPoints.first { $0.key == gran.previousPeriodKey }?.expenses ?? 0
    // бакет-сравнение: неделя/месяц/квартал/год vs предыдущий
}
```
Выдаёт инсайт с заголовком из `gran.monthOverMonthTitle` и периодом из `gran.comparisonPeriodName`.

**Legacy fallback (calendar-month scan):**
- Используется если `periodPoints` пустые или `granularity == .allTime`
- Выполняет O(N) scan по `allTransactions` с фильтрацией по calendar-месяцу
- `momReferenceDate(for: granularityTimeFilter)` — для `.week` = `Date()`, для исторических = конец окна −1 сек

**Инсайт не генерируется для `.allTime`:** `previousPeriodKey == currentPeriodKey` → деление на ноль + дублирующиеся метки в chart.

### Windowing в `generateAllInsights(granularity:)`
```
allTransactions
    → filterByTimeRange(windowStart, windowEnd) → windowedTransactions
    → calculateMonthlySummary(windowedTransactions) → periodSummary
    → generateSpendingInsights(filtered: windowedTransactions, allTransactions: allTransactions)
    → generateIncomeInsights(filtered: windowedTransactions, allTransactions: allTransactions)
    → generateBudgetInsights(transactions: windowedTransactions)
    → generateSavingsInsights(allIncome: windowedIncome, allExpenses: windowedExpenses)
```
`allTransactions` сохраняется для MoM-сравнений (нужна полная история) и forecasting.

### Fast paths (Phase 22)
- `CategoryAggregateService` — O(M) по категориям; `fetchRange(from:to:)` принимает окно гранулярности
- `MonthlyAggregateService` — O(M) по месяцам; `fetchLast(N)` и `fetchRange()`
- `BudgetSpendingCacheService` — O(1) per category; инвалидируется при мутации транзакций
- Fallback: O(N) transaction scan при первом запуске (aggregates ещё не построены)

### SQLite predicate crash fix (Phase 27)
**Проблема:** `fetchRange()` и `fetchLast()` в `CategoryAggregateService` и `MonthlyAggregateService` строили `NSCompoundPredicate(orPredicateWithSubpredicates:)` с одним subpredicate на каждый calendar-месяц. При окне > ~80 месяцев SQLite бросает `Expression tree too large (maximum depth 1000)`.

**Решение:** заменить OR-fan-out на константный предикат из 7 условий:
```
currency == %@ AND year > 0 AND month > 0
AND (year > startYear  OR  (year == startYear  AND month >= startMonth))
AND (year < endYear    OR  (year == endYear    AND month <= endMonth))
```
Размер предиката не зависит от длины окна. `fetchLast(N)` теперь вычисляет `startDate` и делегирует `fetchRange()`.

### `firstTransactionDate` hoisting (Phase 27)
`generateAllInsights(granularity:..., firstTransactionDate:)` принимает опциональный параметр `firstTransactionDate`. Если передан — используется напрямую; если `nil` — выполняется локальный O(N) scan.

В `InsightsViewModel.loadInsightsBackground()` дата вычисляется один раз перед вызовами и передаётся во все granularity-вызовы — устраняет 5× дублирующийся O(N) scan.

### computeGranularities / computeAllGranularities API (Phase 27)
```swift
// Вычислить произвольный набор granularities за один вызов
insightsService.computeGranularities(
    [.week, .month],
    transactions:, baseCurrency:, cacheManager:, currencyService:, balanceFor:,
    firstTransactionDate:
) -> [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])]

// Сахар — вычислить все 5 granularities
insightsService.computeAllGranularities(...)
```
Делегируют в `generateAllInsights()` в цикле. Используются `InsightsViewModel` для двухфазной загрузки.

### Двухфазная прогрессивная загрузка (Phase 27)
`loadInsightsBackground()` делится на два этапа внутри одного `Task.detached`:

| Фаза | Действие | UI-update |
|------|----------|-----------|
| 1 | `computeGranularities([priorityGranularity])` — только текущая вкладка | `MainActor.run` — пользователь видит данные уже после ~1/5 полного времени |
| 2 | `computeGranularities(remaining 4)` + `computeHealthScore` | `MainActor.run` — финальное обновление всех вкладок + health score |

Если пользователь переключил гранулярность пока шёл background task, финальный `applyPrecomputed(for: self.currentGranularity)` использует актуальное значение `currentGranularity` (не захваченное `priorityGranularity`).

### Forecasting/Savings с fixed lookback — почему так
Эти метрики читают из `MonthlyAggregateService` напрямую, минуя window-логику `generateAllInsights`. **По дизайну:** прогноз на конец месяца и аварийный фонд должны отражать текущую недавнюю реальность, а не выбранный бакет графика. Пользователь меняет гранулярность для изучения исторических трендов, но `emergencyFund` должен всегда показывать «сколько месяцев я продержусь прямо сейчас».
