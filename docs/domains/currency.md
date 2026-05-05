# Currency / FX Rates Domain

Three-file split for currency conversion and rate management.

## Architecture

```
CurrencyConverter (static facade, public API)
   ↓
CurrencyRateStore (lock-protected cache + UserDefaults persistence + CurrencyRatesNotifier)
   ↓
Services/Currency/Providers/* (CurrencyRateProviderChain)
       ↓
   JsDelivrCurrencyProvider (primary, jsDelivr CDN + Cloudflare mirror, 200+ currencies)
   NationalBankKZProvider (legacy XML fallback, 8 currencies)
```

## Public API (`CurrencyConverter`)

- `convertSync(_:from:to:)` — synchronous, hot-path safe (uses cached rates)
- `getExchangeRate(date:)` — async with in-flight de-duplication
- `convert(_:from:to:date:)` — async with rate fetch
- `getAllRates()` — full snapshot
- `prewarm()` — runs on app init

## KZT-Pivot Storage

⚠️ **Internal storage is always KZT-pivot**: `cachedRates[X] = "KZT per 1 X"`.

KZT itself is implicit (1.0) and is **NEVER a key** in the dict.

Providers with a different native pivot (jsDelivr=USD) re-pivot via `ExchangeRates.normalized(toPivot: "KZT")` before reaching the store.

**Adding a new provider** — return whatever pivot is natural; the store handles re-pivoting.

## Persistence

Persisted to UserDefaults under key `currency.rates.cache.v1`.

`CurrencyRateStore.init()` restores synchronously so `convertSync` works at T=0 on warm-launch.

⚠️ **Bump the key version** when changing the on-disk format.

## Pre-Warm Behavior

`CurrencyConverter.prewarm()` runs in parallel with `loadData()` in `AppCoordinator.initialize()`.

- Idempotent — skipped when `hasFreshRates` (cache <24h)
- The wait is capped at **2.5s via `withTaskGroup` race** so a slow network never blocks `isFullyInitialized`

⚠️ **Don't remove the cap** — the post-prewarm `invalidateAndRecompute()` re-fires once rates land asynchronously.

## Reactivity for `convertSync` Consumers

`transactionStore.currencyRatesVersion: Int` (`@Observable`) bumps after prewarm.

Aggregator views with `.task(id:)` include it in their trigger so per-currency totals recompute when rates land:
- `ContentView.SummaryTrigger`
- `AccountDetailView.refreshTrigger`
- `CategoryDetailView.RefreshKey`

⚠️ **Adding a new aggregator that reads `convertSync`** — fold `currencyRatesVersion` into its `.task(id:)` key.

## In-Flight De-Duplication

Concurrent `getExchangeRate` calls for the same date share one `Task` via the `inflight` dict keyed by date — **never bypass this**.

## Test Isolation

⚠️ `CurrencyRateStore.shared` persists across test runs via UserDefaults.

Tests that assert `convertSync` returns nil (cross-currency matchers, e.g. `SubscriptionTransactionMatcherTests.findCandidates_matchesCrossCurrencyViaConvertedAmount`) MUST call `CurrencyRateStore.shared.clearAll()` in their suite `init()`.

Otherwise leaked rates from a previous suite cause spurious matches within the 30% default tolerance.
