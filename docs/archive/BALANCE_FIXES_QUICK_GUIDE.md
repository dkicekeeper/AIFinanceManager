# ⚡ Быстрый гайд по исправлению балансов

**Дата:** 2026-02-03
**Для кого:** Developer, который будет фиксить баги
**Время выполнения:** ~1-2 часа для Phase 1

---

## 🎯 Что сломано?

**Проблема:** Internal transfers (переводы между счетами) **не работают** после рефакторинга балансов.

**Симптомы:**
```
До перевода:
  Account A: 1000 ₸
  Account B: 500 ₸

Перевод 100 ₸ от A к B:
  ❌ Account A: 800 ₸ (должно быть 900)
  ❌ Account B: 400 ₸ (должно быть 600)
```

**Причина:**
1. `BalanceCoordinator.processAddTransaction()` не передает `isSource: false` для target account
2. `AccountOperationService.transfer()` НЕ использует BalanceCoordinator (обходит Single Source of Truth)

---

## 🔥 Phase 1: Критические фиксы (1 час)

### Fix 1: BalanceCoordinator - processAddTransaction (5 минут)

**Файл:** `AIFinanceManager/Services/Balance/BalanceCoordinator.swift`

**Строка:** 462

**Было:**
```swift
let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: targetAccount)
```

**Стало:**
```swift
let newBalance = engine.applyTransaction(
    transaction,
    to: currentBalance,
    for: targetAccount,
    isSource: false  // 🔥 CRITICAL FIX
)
```

---

### Fix 2: BalanceCoordinator - processRemoveTransaction (5 минут)

**Файл:** `AIFinanceManager/Services/Balance/BalanceCoordinator.swift`

**Строка:** 499

**Было:**
```swift
let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: targetAccount)
```

**Стало:**
```swift
let newBalance = engine.revertTransaction(
    transaction,
    from: currentBalance,
    for: targetAccount,
    isSource: false  // 🔥 CRITICAL FIX
)
```

---

### Fix 3: AccountOperationService - use BalanceCoordinator (30 минут)

#### Step 1: Обновить протокол

**Файл:** `AIFinanceManager/Protocols/AccountOperationServiceProtocol.swift`

**Было:**
```swift
func transfer(
    from sourceId: String,
    to targetId: String,
    amount: Double,
    currency: String,
    date: String,
    description: String,
    accounts: inout [Account],
    allTransactions: inout [Transaction],
    accountBalanceService: AccountBalanceServiceProtocol,
    saveCallback: () -> Void
)
```

**Стало:**
```swift
func transfer(
    from sourceId: String,
    to targetId: String,
    amount: Double,
    currency: String,
    date: String,
    description: String,
    accounts: inout [Account],
    allTransactions: inout [Transaction],
    balanceCoordinator: BalanceCoordinatorProtocol?,  // 🔥 NEW
    saveCallback: () -> Void
)
```

---

#### Step 2: Обновить реализацию

**Файл:** `AIFinanceManager/Services/Transactions/AccountOperationService.swift`

**Строки:** 17-101

**Было:**
```swift
func transfer(...) {
    // ❌ OLD: Direct modification
    deduct(from: &newAccounts[sourceIndex], amount: amount)
    add(to: &newAccounts[targetIndex], amount: targetAmount)

    accounts = newAccounts

    // Create transaction
    let transferTx = Transaction(...)
    allTransactions.append(transferTx)
    allTransactions.sort { $0.date > $1.date }

    // ❌ OLD: Bypass BalanceCoordinator
    accountBalanceService.syncAccountBalances(accounts)
    saveCallback()
}
```

**Стало:**
```swift
func transfer(
    from sourceId: String,
    to targetId: String,
    amount: Double,
    currency: String,
    date: String,
    description: String,
    accounts: inout [Account],
    allTransactions: inout [Transaction],
    balanceCoordinator: BalanceCoordinatorProtocol?,
    saveCallback: () -> Void
) {
    guard
        let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
        let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
        amount > 0
    else { return }

    let sourceAccount = accounts[sourceIndex]
    let targetAccount = accounts[targetIndex]

    // Calculate target amount with currency conversion
    let targetAmount = convertCurrency(
        amount: amount,
        from: currency,
        to: targetAccount.currency
    )

    // Create transfer transaction
    let createdAt = Date().timeIntervalSince1970
    let id = TransactionIDGenerator.generateID(
        date: date,
        description: description,
        amount: amount,
        type: .internalTransfer,
        currency: currency,
        createdAt: createdAt
    )

    let convertedAmountForSource: Double? = (currency != sourceAccount.currency) ? amount : nil
    let resolvedTargetCurrency = targetAccount.currency

    let transferTx = Transaction(
        id: id,
        date: date,
        description: description,
        amount: amount,
        currency: currency,
        convertedAmount: convertedAmountForSource,
        type: .internalTransfer,
        category: String(localized: "transactionForm.transfer"),
        subcategory: nil,
        accountId: sourceId,
        targetAccountId: targetId,
        accountName: sourceAccount.name,
        targetAccountName: targetAccount.name,
        targetCurrency: resolvedTargetCurrency,
        targetAmount: targetAmount,
        recurringSeriesId: nil,
        recurringOccurrenceId: nil,
        createdAt: createdAt
    )

    // Add transaction to list
    allTransactions.append(transferTx)
    allTransactions.sort { $0.date > $1.date }

    // ✅ NEW: Update balances through BalanceCoordinator
    if let coordinator = balanceCoordinator {
        Task { @MainActor in
            await coordinator.updateForTransaction(
                transferTx,
                operation: .add(transferTx),
                priority: .immediate
            )
        }
    }

    saveCallback()
}
```

---

#### Step 3: Обновить вызов в TransactionsViewModel

**Файл:** `AIFinanceManager/ViewModels/TransactionsViewModel.swift`

**Строки:** 346-362

**Было:**
```swift
accountOperationService.transfer(
    from: sourceId,
    to: targetId,
    amount: amount,
    currency: currency,
    date: date,
    description: description,
    accounts: &accounts,
    allTransactions: &allTransactions,
    accountBalanceService: accountBalanceService,  // ❌ OLD
    saveCallback: { [weak self] in self?.saveToStorageDebounced() }
)
```

**Стало:**
```swift
accountOperationService.transfer(
    from: sourceId,
    to: targetId,
    amount: amount,
    currency: currency,
    date: date,
    description: description,
    accounts: &accounts,
    allTransactions: &allTransactions,
    balanceCoordinator: balanceCoordinator,  // ✅ NEW
    saveCallback: { [weak self] in self?.saveToStorageDebounced() }
)
```

---

## ✅ Проверка (5 минут)

### Test 1: Simple Transfer

```swift
// In Xcode:
// 1. Run app
// 2. Create Account A with 1000 KZT
// 3. Create Account B with 500 KZT
// 4. Transfer 100 KZT from A to B
// 5. Check balances:
//    ✅ A should be 900 KZT
//    ✅ B should be 600 KZT
```

### Test 2: Delete Transfer

```swift
// After Test 1:
// 1. Go to History
// 2. Find the transfer transaction
// 3. Delete it
// 4. Check balances:
//    ✅ A should be 1000 KZT (restored)
//    ✅ B should be 500 KZT (restored)
```

### Test 3: Update Transfer

```swift
// After Test 1:
// 1. Find the transfer transaction
// 2. Edit amount to 200 KZT
// 3. Check balances:
//    ✅ A should be 800 KZT
//    ✅ B should be 700 KZT
```

---

## 🧹 Phase 2: Cleanup (30 минут) - OPTIONAL

### Удалить неиспользуемые методы

**Файл:** `AIFinanceManager/Services/Transactions/AccountOperationService.swift`

**Удалить:**
```swift
// Lines 103-132
func deduct(from account: inout Account, amount: Double) { ... }

// Lines 134-151
func add(to account: inout Account, amount: Double) { ... }
```

**Оставить только:**
```swift
private func convertCurrency(
    amount: Double,
    from fromCurrency: String,
    to toCurrency: String
) -> Double {
    // Keep this - used by transfer()
}
```

---

## 📝 Лог изменений для коммита

```
fix: Correct internal transfer balance updates

CRITICAL FIXES:
- BalanceCoordinator.processAddTransaction: Add isSource=false for target account
- BalanceCoordinator.processRemoveTransaction: Add isSource=false for target account
- AccountOperationService.transfer: Delegate to BalanceCoordinator instead of direct modification
- TransactionsViewModel.transfer: Pass balanceCoordinator to AccountOperationService

PROBLEM:
Internal transfers were incorrectly updating balances because:
1. BalanceCalculationEngine.applyTransaction() defaults to isSource=true
2. Target account was processed as source, causing double subtraction
3. AccountOperationService bypassed BalanceCoordinator (violated Single Source of Truth)

SOLUTION:
- Explicitly pass isSource=false for target account in transfers
- Use BalanceCoordinator.updateForTransaction() for all balance updates
- Remove direct account.balance modifications

TEST CASES:
- ✅ Transfer 100 KZT: A(1000→900), B(500→600)
- ✅ Delete transfer: A(900→1000), B(600→500)
- ✅ Update transfer to 200: A(1000→800), B(500→700)
- ✅ Currency conversion: USD→KZT with exchange rate

BREAKING CHANGES:
- AccountOperationServiceProtocol.transfer() signature changed (added balanceCoordinator parameter)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## 🚨 Troubleshooting

### Проблема: Баланс не обновляется в UI

**Решение:**
```swift
// BalanceCoordinator должен публиковать balances:
self.balances = updatedBalances  // ✅ Trigger @Published
```

**Проверка:**
```swift
// В BalanceCoordinator.processAddTransaction():
#if DEBUG
print("✅ [BalanceCoordinator] Published balances: \(updatedBalances)")
#endif
```

---

### Проблема: Compiler error "Extra argument 'isSource'"

**Причина:** Вы не обновили все вызовы `applyTransaction()`

**Решение:**
```bash
# Найти все вызовы:
grep -r "applyTransaction" --include="*.swift"

# Убедитесь, что для transfers передается isSource explicitly
```

---

### Проблема: Тесты падают

**Решение:**
```swift
// Обновить моки в тестах:
class MockBalanceCoordinator: BalanceCoordinatorProtocol {
    func updateForTransaction(...) async {
        // Mock implementation
    }
}
```

---

## 📚 Дополнительные ресурсы

- **Детальный план:** `BALANCE_OPERATIONS_REFACTORING_PLAN.md`
- **Технический анализ:** `BALANCE_TECHNICAL_ANALYSIS.md`
- **История фиксов:** `BALANCE_FIX_COMPLETE.md`

---

**Автор:** Claude Code Agent
**Дата:** 2026-02-03
**Время выполнения Phase 1:** ~1 час
**Статус:** ✅ Ready to implement
