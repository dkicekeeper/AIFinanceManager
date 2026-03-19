# Исправление: Обнуление балансов при удалении счета

## Проблема

После удаления любого счета у всех остальных счетов обнуляются балансы. После перезапуска приложения балансы восстанавливаются корректно.

## Воспроизведение

1. Создать несколько счетов с балансами
2. Добавить транзакции на эти счета
3. Удалить один из счетов
4. **Результат:** У всех оставшихся счетов баланс становится 0
5. Перезапустить приложение
6. **Результат:** Балансы восстанавливаются

## Корневая причина (ОБНОВЛЕНО)

**Примечание:** Первоначально была найдена и исправлена проблема в `CoreDataRepository`, но тестирование показало, что настоящая корневая причина находилась в `BalanceCoordinator`.

### Архитектура баланса счетов

В приложении баланс счета хранится в двух местах:

1. **В памяти** (текущий, актуальный):
   - `BalanceCoordinator.balances: [String: Double]` - рассчитывается динамически из транзакций

2. **В Core Data** (кеш для быстрой загрузки):
   - `AccountEntity.balance: Double` - используется при инициализации `Account.initialBalance`

### Поток ошибки (НАСТОЯЩАЯ ПРИЧИНА)

1. Пользователь удаляет счет
2. `TransactionStore.deleteAccount()` удаляет счет из массива и вызывает `persistAccounts()`
3. Observer в `AccountsViewModel` получает обновление: `accounts` теперь содержит на 1 счет меньше
4. Срабатывает `setupTransactionStoreObserver()` → вызывается `syncInitialBalancesToCoordinator()`
5. **ПРОБЛЕМА:** `syncInitialBalancesToCoordinator()` вызывает `coordinator.registerAccounts(accounts)`
6. **КРИТИЧЕСКАЯ ОШИБКА в `BalanceCoordinator.registerAccounts()`:**
   ```swift
   let initialBalances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.initialBalance ?? 0) })
   self.balances = initialBalances  // ❌ Перезаписывает ВСЕ балансы нулями!
   ```
7. Для счетов с `shouldCalculateFromTransactions = true`, `initialBalance` равен 0
8. `self.balances` **полностью перезаписывается** → все текущие балансы заменяются на 0
9. UI обновляется из `balances` → показывает 0 для всех счетов
10. После перезапуска `BalanceCoordinator` правильно инициализируется и пересчитывает балансы из транзакций

### Диаграмма потока данных

```
Account Creation
---------------
User creates account with initialBalance=1000
  ↓
TransactionStore.addAccount()
  ↓
AccountEntity.balance = 1000  ✅ Correct
  ↓
BalanceCoordinator initializes with balance=1000


After Transactions
-----------------
User adds expense -500
  ↓
BalanceCoordinator calculates: 1000 - 500 = 500
  ↓
balances["account123"] = 500  ✅ Current balance in memory
  ↓
AccountEntity.balance = 1000  ⚠️ Still shows initialBalance in DB


Account Deletion (BEFORE FIX) - REAL BUG
-----------------------------------------
User deletes another account
  ↓
TransactionStore.deleteAccount() removes from array
  ↓
Observer triggers in AccountsViewModel
  ↓
syncInitialBalancesToCoordinator() called
  ↓
coordinator.registerAccounts(accounts) called  ❌ HERE!
  ↓
self.balances = [
  "account1": 0,  // was 500
  "account3": 0   // was 2500
]  ❌ ALL BALANCES RESET TO initialBalance (which is 0)!
  ↓
UI updates from coordinator.balances  ❌ Shows 0 balance
  ↓
App restart → BalanceCoordinator recalculates → Shows 500  ✅
```

## Решение

### Двухэтапное исправление

#### Этап 1: CoreDataRepository (Профилактическое исправление)

### Изменения в `CoreDataRepository.swift`

#### 1. Метод `saveAccounts()` (строка 210-222)

**До:**
```swift
if let existing = existingDict[account.id] {
    // Update existing
    existing.name = account.name
    existing.balance = account.initialBalance ?? 0  // ❌ Bug
    existing.currency = account.currency
    existing.logo = account.bankLogo.rawValue
    existing.isDeposit = account.isDeposit
    existing.bankName = account.depositInfo?.bankName
}
```

**После:**
```swift
if let existing = existingDict[account.id] {
    // Update existing
    existing.name = account.name
    // ⚠️ CRITICAL FIX: Don't overwrite balance here - it's managed by BalanceCoordinator
    // Only update balance when creating new accounts
    // existing.balance = account.initialBalance ?? 0  // ❌ This was causing balance reset
    existing.currency = account.currency
    existing.logo = account.bankLogo.rawValue
    existing.isDeposit = account.isDeposit
    existing.bankName = account.depositInfo?.bankName
}
```

#### 2. Метод `saveAccountsSync()` (строка 376-388)

Аналогичное исправление для синхронной версии метода.

#### Этап 2: BalanceCoordinator (НАСТОЯЩЕЕ ИСПРАВЛЕНИЕ)

**Изменения в `BalanceCoordinator.swift`:**

**До:**
```swift
func registerAccounts(_ accounts: [Account]) async {
    let accountBalances = accounts.map { AccountBalance.from($0) }
    store.registerAccounts(accountBalances)

    let initialBalances = Dictionary(uniqueKeysWithValues: accounts.map {
        ($0.id, $0.initialBalance ?? 0)
    })
    cache.setBalances(initialBalances)

    self.balances = initialBalances  // ❌ Bug - overwrites ALL balances!
}
```

**После:**
```swift
func registerAccounts(_ accounts: [Account]) async {
    let accountBalances = accounts.map { AccountBalance.from($0) }
    store.registerAccounts(accountBalances)

    // ⚠️ CRITICAL FIX: Only initialize balances for NEW accounts
    var updatedBalances = self.balances  // Preserve existing balances

    for account in accounts {
        // Only set initial balance if account is NOT already registered
        if updatedBalances[account.id] == nil {
            let initialBalance = account.initialBalance ?? 0
            updatedBalances[account.id] = initialBalance
            cache.setBalance(initialBalance, for: account.id)
        }
    }

    self.balances = updatedBalances  // ✅ Preserves existing balances!
}
```

### Логика исправления

**Принцип:**
- `BalanceCoordinator.balances` содержит **актуальные** балансы, рассчитанные из транзакций
- При повторной регистрации счетов (например, после удаления одного) нужно **сохранить** существующие балансы
- Только **новые** счета инициализируются с `initialBalance`
- Существующие счета **сохраняют** свои текущие балансы

**Почему это работает:**
1. При создании НОВОГО счета `balances[accountId]` равен `nil` → устанавливается `initialBalance` ✅
2. При повторной регистрации существующих счетов `balances[accountId]` уже существует → баланс сохраняется ✅
3. При удалении счета остальные счета перерегистрируются, но их балансы НЕ перезаписываются ✅
4. `BalanceCoordinator` продолжает управлять актуальными балансами в памяти ✅

## Тестирование

### Сценарий 1: Удаление счета
1. ✅ Создать 3 счета с балансами 1000, 2000, 3000
2. ✅ Добавить транзакции (расходы -500 на каждый)
3. ✅ Текущие балансы: 500, 1500, 2500
4. ✅ Удалить второй счет
5. ✅ **Ожидаемо:** Балансы первого и третьего счетов остаются 500 и 2500
6. ✅ **Результат:** PASSED - балансы не обнулились

### Сценарий 2: Перезапуск приложения
1. ✅ После теста 1 перезапустить приложение
2. ✅ **Ожидаемо:** Балансы восстанавливаются корректно (500 и 2500)
3. ✅ **Результат:** PASSED

### Сценарий 3: Создание нового счета
1. ✅ Создать новый счет с initialBalance=5000
2. ✅ **Ожидаемо:** AccountEntity.balance = 5000
3. ✅ **Результат:** PASSED

## Дополнительные замечания

### Потенциальные улучшения

В будущем можно добавить:

1. **Периодическая синхронизация балансов:**
   ```swift
   // In BalanceCoordinator
   func syncBalancesToCoreData() async {
       for (accountId, balance) in balances {
           await repository.updateAccountBalance(accountId: accountId, balance: balance)
       }
   }
   ```

2. **Отдельный метод для обновления баланса:**
   ```swift
   // In CoreDataRepository
   func updateAccountBalance(accountId: String, balance: Double) async {
       // Update only the balance field, not all account properties
   }
   ```

Однако эти улучшения **не критичны**, так как:
- `BalanceCoordinator` пересчитывает балансы корректно при каждом запуске
- Балансы сохраняются в памяти и работают правильно во время сессии приложения
- `AccountEntity.balance` используется только для инициализации, не для отображения

### Связанные файлы

- `AIFinanceManager/Services/Balance/BalanceCoordinator.swift` - **ОСНОВНОЕ ИСПРАВЛЕНИЕ** - сохранение балансов при перерегистрации
- `AIFinanceManager/Services/CoreDataRepository.swift` - профилактическое исправление методов сохранения
- `AIFinanceManager/ViewModels/AccountsViewModel.swift` - вызывает `syncInitialBalancesToCoordinator()`
- `AIFinanceManager/ViewModels/TransactionStore.swift` - вызывает `persistAccounts()`
- `AIFinanceManager/CoreData/Entities/AccountEntity+CoreDataClass.swift` - конвертация между моделями

## Хронология исправления

### 2026-02-10 (Попытка 1)
- Исправлена проблема в `CoreDataRepository.saveAccounts()`
- Закомментирована строка `existing.balance = account.initialBalance ?? 0`
- **Результат:** Проблема НЕ решена - балансы всё равно обнулялись

### 2026-02-10 (Попытка 2 - УСПЕХ)
- Найдена настоящая причина в `BalanceCoordinator.registerAccounts()`
- Исправлена перезапись `self.balances` при повторной регистрации
- **Результат:** Проблема РЕШЕНА ✅

## Статус

✅ **ИСПРАВЛЕНО** - баланс больше не обнуляется при удалении счета
✅ **ОПТИМИЗИРОВАНО** - балансы сохраняются в Core Data, пересчет при запуске устранен

Дата исправления: 2026-02-10

---

## Оптимизация: Устранение пересчета балансов при запуске

### Проблема производительности

После исправления основного бага выяснилось, что приложение пересчитывает балансы всех 36 счетов из 18,248 транзакций при каждом запуске, что занимает значительное время.

### Решение

Реализована система персистентности балансов в Core Data:

#### 1. Методы сохранения балансов в `CoreDataRepository.swift`

**Одиночное обновление:**
```swift
func updateAccountBalance(accountId: String, balance: Double) {
    Task.detached(priority: .userInitiated) { [weak self] in
        try await self.saveCoordinator.performSave(operation: "updateAccountBalance") { context in
            let fetchRequest = AccountEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", accountId)
            if let account = try context.fetch(fetchRequest).first {
                account.balance = balance
            }
        }
    }
}
```

**Пакетное обновление (критично для избежания конфликтов):**
```swift
func updateAccountBalances(_ balances: [String: Double]) {
    Task.detached(priority: .userInitiated) { [weak self] in
        try await self.saveCoordinator.performSave(operation: "updateAccountBalances") { context in
            let accountIds = Array(balances.keys)
            let fetchRequest = AccountEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", accountIds)
            let accounts = try context.fetch(fetchRequest)
            for account in accounts {
                if let accountId = account.id, let newBalance = balances[accountId] {
                    account.balance = newBalance
                }
            }
        }
    }
}
```

#### 2. Интеграция в `BalanceCoordinator.swift`

**Сохранение после пересчета:**
```swift
private func persistBalances(_ balances: [String: Double]) {
    guard let coreDataRepo = repository as? CoreDataRepository else { return }
    coreDataRepo.updateAccountBalances(balances)  // ✅ Batch update
}
```

**Вызовы в методах обработки транзакций:**
- `processAddTransaction()` → вызывает `persistBalance()` после обновления баланса
- `processRemoveTransaction()` → вызывает `persistBalance()` после обновления баланса
- `processRecalculateAll()` → вызывает `persistBalances()` после пересчета всех балансов

#### 3. Удаление пересчета при запуске в `AppCoordinator.swift`

**До:**
```swift
// CRITICAL: Recalculate balances after loading transactions
await balanceCoordinator.recalculateAll(
    accounts: accountsViewModel.accounts,
    transactions: transactionsViewModel.allTransactions
)
```

**После:**
```swift
// ✅ OPTIMIZED 2026-02-10: No need to recalculate on launch
// Balances are now persisted to Core Data and loaded correctly during registerAccounts()
#if DEBUG
print("✅ [AppCoordinator] Balances loaded from Core Data - skipping recalculation")
#endif
```

### Поток данных

```
App Launch
----------
1. TransactionStore loads accounts from Core Data
   AccountEntity.balance → Account.initialBalance  ✅ Restored from DB

2. BalanceCoordinator.registerAccounts() called
   account.initialBalance → balances[accountId]  ✅ Loaded from Core Data

3. UI displays balances  ✅ Instant, no recalculation needed


Transaction Added
----------------
1. BalanceCoordinator.updateForTransaction() called
2. Balance recalculated for affected account(s)
3. persistBalance() saves to Core Data  💾
4. UI updates


Account Deleted
--------------
1. TransactionStore.deleteAccount() removes account
2. AccountsViewModel observer triggers
3. BalanceCoordinator.registerAccounts() called
4. Preserves existing balances  ✅ (our bug fix)
5. No recalculation needed
```

### Результаты

- ✅ Балансы загружаются из Core Data мгновенно
- ✅ Пересчет только при изменении транзакций
- ✅ Пакетное обновление избегает конфликтов сохранения
- ✅ Устранена задержка при запуске приложения

### Связанные файлы (Оптимизация)

- `AIFinanceManager/ViewModels/AppCoordinator.swift` - удален `recalculateAll()` при инициализации
- `AIFinanceManager/Services/Balance/BalanceCoordinator.swift` - добавлены `persistBalance()` и `persistBalances()`
- `AIFinanceManager/Services/CoreDataRepository.swift` - добавлены `updateAccountBalance()` и `updateAccountBalances()`
- `AIFinanceManager/Services/DataRepositoryProtocol.swift` - расширен протокол методами обновления балансов
- `AIFinanceManager/Services/UserDefaultsRepository.swift` - добавлены заглушки для протокола
- `AIFinanceManager/Services/CSV/CSVImportCoordinator.swift` - добавлен `recalculateAll()` после завершения импорта

Дата оптимизации: 2026-02-10

---

## Дополнительное исправление: Балансы при CSV импорте

### Проблема

После импорта CSV большинство балансов остаются 0, только некоторые обновляются. Это происходит потому, что `CSVImportCoordinator` регистрирует счета и устанавливает начальные балансы, но **не пересчитывает балансы на основе импортированных транзакций**.

### Решение

Добавлен вызов `recalculateAll()` в конце `CSVImportCoordinator.importTransactions()`:

```swift
// Register accounts in BalanceCoordinator
if let accountsVM = accountsViewModel,
   let balanceCoordinator = transactionsViewModel.balanceCoordinator {
    await balanceCoordinator.registerAccounts(accountsVM.accounts)

    for account in accountsVM.accounts {
        let initialBalance = accountsVM.getInitialBalance(for: account.id) ?? 0
        await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)

        if !account.shouldCalculateFromTransactions {
            await balanceCoordinator.markAsManual(account.id)
        }
    }

    // ✅ CRITICAL: Recalculate balances after CSV import
    // This ensures all accounts reflect the imported transactions
    await balanceCoordinator.recalculateAll(
        accounts: accountsVM.accounts,
        transactions: transactionsViewModel.allTransactions
    )
}
```

### Логика

1. CSV импортирует транзакции → добавляет их в TransactionStore
2. Регистрирует счета в BalanceCoordinator
3. **НОВОЕ:** Пересчитывает балансы всех счетов на основе всех транзакций (включая импортированные)
4. Сохраняет пересчитанные балансы в Core Data через `persistBalances()`
5. При следующем запуске балансы загружаются из Core Data

### Отличие от запуска приложения

- **При запуске приложения:** Балансы загружаются из Core Data (НЕТ пересчета)
- **После CSV импорта:** Балансы **ПЕРЕСЧИТЫВАЮТСЯ** на основе ВСЕХ транзакций (старых + новых), затем сохраняются в Core Data

Это правильное поведение, так как:
- После импорта данные изменились → нужен пересчет
- После пересчета балансы сохраняются → следующий запуск будет быстрым
