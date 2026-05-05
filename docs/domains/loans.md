# Loans Domain

Payment tracking, reconciliation, and amortization.

## Persistence

`LoanInfo` persisted via `loanInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6) — mirrors [DepositInfo pattern](deposits.md).

## LoanPaymentService

`nonisolated enum` providing:
- annuity formula
- amortization schedule
- payment breakdown
- early repayment
- reconciliation

## Auto-Calculate `monthlyPayment`

`LoanInfo.init` auto-calculates `monthlyPayment` when `nil` is passed.

⚠️ **Pass `nil` to force recalculation** after principal/rate/term changes.

## Reconciliation

`reconcileLoanPayments` is **synchronous** with `onTransactionCreated` callback.

⚠️ **Callers MUST collect transactions in array, then batch-persist via `transactionStore.add()` after reconciliation completes.**

Do NOT spawn fire-and-forget `Task {}` inside the callback — creates race condition where loan state diverges from transaction records.

## Centralized Reconciliation Point

`AccountsManagementView` is the centralized reconciliation point for both loans AND deposits on `.task {}` appear.

⚠️ **`reconcileAllLoans` must be called globally** — not just per-loan in detail view. If user doesn't visit each loan's detail screen, reconciliation is skipped.

## Every Financial Mutation Creates a Transaction

| Method | Transaction Type |
|--------|------------------|
| `makeManualPayment` | `.loanPayment` |
| `makeEarlyRepayment` | `.loanEarlyRepayment` |

Both return `Transaction?` for the caller to persist.

## LoanTransactionMatcher

Conforms to the same matcher signature as `SubscriptionTransactionMatcher` — accepts `AmountMatchMode` (`.all` / `.tolerance` / `.exact`). Defined alongside `SubscriptionTransactionMatcher` in `Services/Recurring/SubscriptionTransactionMatcher.swift`.

New matchers should follow the same signature to plug into `LinkPaymentsView`.

## Link-Payments UI

UI wrapper: `LoanLinkPaymentsView` — uses shared `LinkPaymentsView` (`Views/Components/LinkPayments/LinkPaymentsView.swift`).

Provides full linking UX (filters, sheets, search, caches, background scan, haptic).

⚠️ **Don't duplicate the state machine** — wrap `LinkPaymentsView` with `findCandidates` + `performLink` `@Sendable` closures.
