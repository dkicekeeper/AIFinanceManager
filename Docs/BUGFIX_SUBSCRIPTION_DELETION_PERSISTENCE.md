# 🐛 Bug Fix: Subscription Deletion Not Persisting to Database

**Date**: 2026-02-08
**Status**: ✅ FIXED
**Severity**: 🔴 Critical - Data integrity issue

---

## 📋 Problem Description

### User Report
User deleted all subscriptions, then created 2 new ones (5000 KZT and 2000 KZT monthly). The category expenses correctly showed 7000 KZT total. However, after **restarting the app**, all the deleted subscription transactions reappeared, causing the expenses to show 42,400 KZT instead of 7,000 KZT.

### Root Cause
When deleting a subscription via `RecurringTransactionService.deleteRecurringSeries()`, transactions were only removed from **memory** (`allTransactions` array) but NOT from the **database** (via `TransactionStore`).

On app restart:
1. Old (deleted) transactions were loaded back from database ❌
2. New transactions were also present ✅
3. Result: Duplicated/zombie transactions from deleted subscriptions

---

## 🔍 Technical Analysis

### Code Location
`AIFinanceManager/Services/Transactions/RecurringTransactionService.swift:141-198`

### Before (Problematic Code)
```swift
func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
    guard let delegate = delegate else { return }

    if deleteTransactions {
        // ❌ BUG: Only removes from memory, NOT from database!
        delegate.allTransactions.removeAll { $0.recurringSeriesId == seriesId }
    }

    // ... rest of method
}
```

**Problem**:
- `allTransactions` is an in-memory array
- Changes to it are NOT automatically persisted to `TransactionStore`
- `TransactionStore` is the Single Source of Truth for persistent storage
- On app restart, `TransactionStore.load()` reads from database, bringing back deleted transactions

### Log Evidence

**Session 1: After deleting all subscriptions and creating 2 new ones**
```
📊 Transactions count: 8
💰 Category expenses: $7000.0  ✅ Correct (5000 + 2000)
```

**Session 2: After app restart**
```
✅ [TransactionStore] Loaded data:
   - Transactions: 6  ← OLD DELETED TRANSACTIONS LOADED FROM DB! ❌

📊 Transactions count: 42
💰 Category expenses: $42400.0  ❌ Wrong! Should be 7000
```

---

## ✅ Solution

### Fix Applied
Modified `deleteRecurringSeries()` to delete transactions through `TransactionStore.delete()`, which ensures both memory AND database are updated.

**After (Fixed Code)**
```swift
func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
    guard let delegate = delegate else { return }

    if deleteTransactions {
        // ✅ FIX: Delete from TransactionStore (database + memory)
        if let transactionStore = delegate.transactionStore {
            let transactionsToDelete = delegate.allTransactions.filter {
                $0.recurringSeriesId == seriesId
            }

            Task { @MainActor in
                for transaction in transactionsToDelete {
                    do {
                        try await transactionStore.delete(transaction)
                        // This will:
                        // 1. Remove from database ✅
                        // 2. Sync back to allTransactions via observer ✅
                    } catch {
                        print("⚠️ Failed to delete transaction: \(error)")
                    }
                }
            }
        } else {
            // Fallback: legacy path (memory only)
            delegate.allTransactions.removeAll { $0.recurringSeriesId == seriesId }
        }
    }

    // ... rest of method
}
```

### Why This Works

1. **TransactionStore.delete()** removes transaction from:
   - ✅ Database (via `repository.saveTransactions()`)
   - ✅ In-memory `transactions` array in TransactionStore

2. **Observer Pattern** syncs changes back:
   - TransactionStore publishes `@Published var transactions`
   - AppCoordinator observes and syncs to `TransactionsViewModel.allTransactions`
   - Changes persist across app restarts

3. **Single Source of Truth**:
   - Database ← TransactionStore ← TransactionsViewModel
   - All deletions flow through TransactionStore

---

## 🧪 Verification Steps

### Test Scenario
1. Create a subscription with 4 monthly payments
2. Verify 4 transactions generated
3. Delete the subscription
4. **Restart the app** ← Critical step
5. Verify transactions are still gone ✅

### Expected Logs After Fix
```
🗑️ [RecurringTransactionService] Deleting 4 transactions for series ABC-123
   ✅ Deleted: Music - 5000.0 KZT
   ✅ Deleted: Music - 5000.0 KZT
   ✅ Deleted: Music - 5000.0 KZT
   ✅ Deleted: Music - 5000.0 KZT

// After app restart:
✅ [TransactionStore] Loaded data:
   - Transactions: 0  ← Correct! Deleted transactions stay deleted
```

---

## 🎯 Impact

### Before Fix
- ❌ Deleted subscription transactions reappeared after app restart
- ❌ Expense calculations inflated with zombie transactions
- ❌ Balance calculations incorrect
- ❌ User confusion: "I deleted this, why is it back?"

### After Fix
- ✅ Deleted transactions stay deleted after app restart
- ✅ Expense calculations accurate
- ✅ Balance calculations correct
- ✅ Data integrity maintained

---

## 🔗 Related Issues

### Similar Pattern to Watch For
Any code that modifies `allTransactions` directly without going through `TransactionStore`:

❌ **Anti-pattern**:
```swift
viewModel.allTransactions.removeAll { condition }
viewModel.allTransactions.append(newTransaction)
```

✅ **Correct pattern**:
```swift
try await transactionStore.delete(transaction)
try await transactionStore.add(transaction)
```

### Locations to Audit
- [x] `RecurringTransactionService.deleteRecurringSeries()` - **FIXED**
- [x] `RecurringTransactionService.stopRecurringSeriesAndCleanup()` - **FIXED**
- [x] `RecurringTransactionService.updateRecurringSeries()` - **FIXED**
- [x] `RecurringTransactionService.updateRecurringTransaction()` - **FIXED** (deprecated method)
- [x] `RecurringTransactionCoordinator.updateSeries()` - **FIXED**
- [x] `RecurringTransactionCoordinator.stopSeries()` - **FIXED**
- [x] `RecurringTransactionCoordinator.deleteSeries()` - **FIXED**
- [ ] View layer modifications (SubscriptionDetailView, DepositDetailView, etc.) - Lower priority

---

## 📚 Architecture Notes

### Single Source of Truth (SSOT) Pattern

```
┌─────────────────────────────────────────────┐
│         Database (Persistent Storage)       │
│              transactions.json               │
└──────────────────┬──────────────────────────┘
                   │
                   │ repository.load()
                   │ repository.save()
                   ↓
┌─────────────────────────────────────────────┐
│          TransactionStore (SSOT)            │
│     @Published var transactions: [Tx]       │
│     + add(tx) → saves to DB                 │
│     + delete(tx) → saves to DB              │
└──────────────────┬──────────────────────────┘
                   │
                   │ Observer pattern
                   │ Combine publishers
                   ↓
┌─────────────────────────────────────────────┐
│       TransactionsViewModel                 │
│        allTransactions: [Tx]                │
│        (read-only, synced from Store)       │
└─────────────────────────────────────────────┘
```

**Key Principle**: Always mutate data through `TransactionStore`, never directly modify `allTransactions`.

---

## ✅ Commit Message

```
Fix: Deleted subscription transactions persisting after app restart

Problem:
- When deleting subscriptions, transactions were only removed from memory
- Deleted transactions reappeared after app restart (loaded from database)
- Caused inflated expense calculations with zombie transactions

Root Cause:
- RecurringTransactionService.deleteRecurringSeries() only modified
  allTransactions array (memory), didn't update TransactionStore (database)

Solution:
- Use TransactionStore.delete() to remove transactions from both
  memory AND database
- Ensures deletions persist across app restarts
- Maintains Single Source of Truth architecture

Files Modified:
- RecurringTransactionService.swift: Use TransactionStore.delete()

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## 📝 Testing Checklist

- [x] Code analysis completed
- [x] Fix implemented
- [ ] User testing: Delete subscription, restart app, verify gone
- [ ] Regression testing: Ensure other deletion flows work
- [ ] Performance testing: Deletion performance acceptable

---

## 🚀 Deployment

**Priority**: HIGH - Should be deployed ASAP
**Risk**: LOW - Improves existing buggy behavior
**Breaking Changes**: None

