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

## Корневая причина

### Архитектура баланса счетов

В приложении баланс счета хранится в двух местах:

1. **В памяти** (текущий, актуальный):
   - `BalanceCoordinator.balances: [String: Double]` - рассчитывается динамически из транзакций

2. **В Core Data** (кеш для быстрой загрузки):
   - `AccountEntity.balance: Double` - используется при инициализации `Account.initialBalance`

### Поток ошибки

1. Пользователь удаляет счет
2. `TransactionStore.deleteAccount()` вызывает `persistAccounts()`
3. `CoreDataRepository.saveAccounts()` обновляет **все** счета в Core Data
4. **Проблема:** При обновлении происходило:
   ```swift
   existing.balance = account.initialBalance ?? 0  // ❌ ОШИБКА
   ```
5. Для счетов с `shouldCalculateFromTransactions = true`, `initialBalance` часто равен 0
6. Это перезаписывало актуальный баланс в `AccountEntity.balance` нулем
7. При следующей загрузке UI обновлялся, но `BalanceCoordinator` ещё не пересчитал балансы
8. После перезапуска `BalanceCoordinator` правильно инициализировался и пересчитывал балансы

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


Account Deletion (BEFORE FIX)
-----------------------------
User deletes another account
  ↓
TransactionStore.deleteAccount()
  ↓
persistAccounts() saves ALL remaining accounts
  ↓
saveAccounts() loops through accounts
  ↓
existing.balance = account.initialBalance ?? 0  ❌ BUG!
  ↓
AccountEntity.balance = 0  ❌ Overwrites with initialBalance
  ↓
UI updates from AccountEntity  ❌ Shows 0 balance
  ↓
App restart → BalanceCoordinator recalculates → Shows 500  ✅
```

## Решение

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

### Логика исправления

**Принцип:**
- `AccountEntity.balance` должен обновляться **только при создании** нового счета
- При обновлении существующего счета `balance` **не трогаем**, так как это поле управляется `BalanceCoordinator`
- `BalanceCoordinator` хранит актуальные балансы в памяти и пересчитывает их при необходимости

**Почему это работает:**
1. При создании счета `AccountEntity.balance` устанавливается из `initialBalance` ✅
2. При обновлении счета (изменение имени, валюты и т.д.) `balance` сохраняется ✅
3. При удалении другого счета `balance` остальных счетов не перезаписывается ✅
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

- `AIFinanceManager/Services/CoreDataRepository.swift` - исправлены методы сохранения
- `AIFinanceManager/ViewModels/TransactionStore.swift` - вызывает `persistAccounts()`
- `AIFinanceManager/Services/Balance/BalanceCoordinator.swift` - управляет балансами в памяти
- `AIFinanceManager/CoreData/Entities/AccountEntity+CoreDataClass.swift` - конвертация между моделями

## Статус

✅ **ИСПРАВЛЕНО** - баланс больше не обнуляется при удалении счета

Дата исправления: 2026-02-10
