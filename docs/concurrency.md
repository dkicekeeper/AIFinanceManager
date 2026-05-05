# Swift 6 Concurrency & CoreData Threading

Critical patterns for thread safety in this codebase. Project ships with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_STRICT_CONCURRENCY = minimal`.

## Implicit MainActor Isolation

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means **ALL types are implicitly `@MainActor`** unless explicitly `nonisolated`.

- `nonisolated` on a type opts it out of implicit MainActor — use for services that must run off main thread
- `Task {}` inside `@MainActor` class inherits MainActor — `Task { @MainActor in }` is redundant
- `Task { @MainActor in }` IS needed inside nonisolated closures, audio callbacks
- **Modifier order**: access modifier ALWAYS first — `private nonisolated func`, `private nonisolated(unsafe) var`. NEVER `nonisolated private` or `nonisolated(unsafe) private`
- **`@NSManaged` order**: `@NSManaged public nonisolated var` — attribute first, access level second, `nonisolated` third
- **`nonisolated(unsafe)`** only for mutable `static var` / stored properties with no actor protection — always add a comment explaining the accepted race

## Sendable Types in iOS 26 SDK

These are `Sendable` in iOS 26 — use plain `nonisolated static let`, NOT `nonisolated(unsafe) static let`:

- `DateFormatter`
- `Logger`
- `Calendar`
- `NumberFormatter`

## DataSnapshot Pattern (capturing MainActor data into Sendable struct)

When you need to do heavy computation off MainActor, bundle MainActor-isolated data into a `Sendable` struct first, then pass it through the entire computation chain.

Example: [InsightsService.DataSnapshot](../Tenra/Services/Insights/InsightsService.swift) bundles transactions, categories, recurringSeries, accounts, and `balanceFor` closure — built on MainActor before `Task.detached`, threaded through the entire computation chain.

## CoreData Entity Mutations

All CoreData entity property mutations MUST be wrapped in `context.perform { }`:

```swift
// ❌ WRONG — Causes Swift 6 concurrency violations
func updateAccount(_ entity: AccountEntity, balance: Double) {
    entity.balance = balance
}

// ✅ CORRECT — Thread-safe mutation
func updateAccount(_ entity: AccountEntity, balance: Double) {
    context.perform {
        entity.balance = balance
    }
}
```

### Repository pattern with CoreData

Repository classes use `nonisolated final class … @unchecked Sendable` — safe because all mutations go through `context.performAndWait`.

`CoreDataStack.newBackgroundContext()` must be `nonisolated` — repositories call it from nonisolated context.

Model struct `init` and computed properties accessed from nonisolated services need `nonisolated`.

```swift
// ✅ Pattern applied in AccountRepository, CategoryRepository, etc.
func saveAccountsInternal(...) throws {
    context.perform {
        existing.name = account.name
        existing.balance = account.balance
        // ... all mutations inside perform block
    }
}

// ✅ CoreDataStack
final class CoreDataStack: @unchecked Sendable {
    nonisolated(unsafe) static let shared = CoreDataStack()
}
```

## Sendable Conformance

- Mark actor request types as `Sendable`
- Use `@Sendable` for completion closures
- Use `@unchecked Sendable` for singletons with internal synchronization

```swift
// ✅ Example: BalanceUpdateRequest
struct BalanceUpdateRequest: Sendable {
    let completion: (@Sendable () -> Void)?
    enum BalanceUpdateSource: Sendable { ... }
}
```

## Main Actor Isolation Patterns

- Use `.main` queue for `NotificationCenter` observers in ViewModels
- Mark static constants with `nonisolated(unsafe)` when needed
- Wrap captured state access in `Task { @MainActor in ... }` (when inside a nonisolated context)

```swift
// ✅ NotificationCenter observers
NotificationCenter.default.addObserver(
    forName: .someNotification,
    queue: .main  // ← Ensures MainActor context
) { ... }

// ✅ Static constants
@MainActor class AppSettings {
    nonisolated(unsafe) static let defaultCurrency = "KZT"
}
```

## CoreData Gotchas

- **OR-per-month predicate crash**: Never build `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month — exceeds SQLite expression tree depth limit (1000). Use a constant 7-condition range predicate instead.
- **`NSDecimalNumber.compare()` gotcha**: `number.compare(.zero)` doesn't compile — always write `number.compare(NSDecimalNumber.zero)`
- **`performFetch()` + `rebuildSections()` are synchronous on MainActor** — sections fully updated before the next line.
- **`resetAllData()` invalidates FRC**: Destroys/recreates the persistent store. FRC holders must observe `storeDidResetNotification` and call `setup()` to recreate. See `TransactionPaginationController.handleStoreReset()`.
- **FRC delegate must rebuild synchronously**: Use `MainActor.assumeIsolated { rebuildSections() }` — NOT `Task { @MainActor in }` which creates async hop allowing stale section access.
- **Entity resolution case-sensitivity**: `resolveCategoryByName` must use case-insensitive comparison. When cache HITs on a case-variant, return the **stored** entity name (not the input name).
- **NEVER use `NSBatchDeleteRequest` then `context.save()` on the SAME context** when deleted objects have inverse relationships. Use `context.delete()` instead.
- **`viewContext.perform { }` runs on MainActor** — viewContext is MainActor-bound, so its perform queue blocks UI. Use `newBackgroundContext()` for heavy ops (purgeHistory, batch deletes, large fetches that don't need UI synchronicity).

## DateFormatter Threading

On iOS 26+ target `DateFormatter` is `Sendable` — use `nonisolated static let`. On older targets:
- `@MainActor private static let`
- Format strings on MainActor before `Task.detached`
- Pass `String`, not the formatter

## Cross-File Extension Access Control

- `private` is file-scoped — extensions in OTHER files can't access it
- Shared helpers → `internal` (no modifier); same file only → `private`
- **Extension file imports are not inherited**: Each file needs its own `import os`, `import CoreData`, etc.

## Compiler Warnings to Watch

- **`internal(set) var` on internal properties** — redundant (default is already internal), generates warning; just use `var`
- **`defer` at end of scope** — generates "execution is not deferred" warning; replace with direct inline assignment
- **`@ObservationIgnored` only works inside `@Observable` classes** — on a regular `class`, `struct`, or `@MainActor`-class without `@Observable`, the attribute is silently ignored. Remove it if `@Observable` is removed from the class.

## @Observable Rules

### `@ObservationIgnored` for Dependencies

Any property that is a service, repository, cache, formatter, or reference to another VM/Coordinator **must** be marked `@ObservationIgnored`:

```swift
// ❌ WRONG — SwiftUI tracks repository and currencyService
@Observable @MainActor class SomeViewModel {
    let repository: DataRepositoryProtocol
    let currencyService = TransactionCurrencyService()
    var isLoading = false
}

// ✅ CORRECT — only isLoading is tracked
@Observable @MainActor class SomeViewModel {
    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let currencyService = TransactionCurrencyService()
    var isLoading = false
}
```

**Rule of thumb**: if a property doesn't change after `init` or its change shouldn't trigger UI — use `@ObservationIgnored`.

**Important**: `weak var` dependencies also need `@ObservationIgnored`, not just `let`. SwiftUI tracks accesses at instance level.

### ViewModel Storage in Views

| Situation | Correct Pattern |
|-----------|----------------|
| VM created inside View | `@State var vm = SomeViewModel()` |
| VM passed from outside (read-only) | `let vm: SomeViewModel` |
| VM passed from outside (need `$binding`) | `@Bindable var vm: SomeViewModel` |
| VM from environment | `@Environment(SomeViewModel.self) var vm` |

Never use `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — those are for old `ObservableObject`.

### Current Exceptions (intentionally observable)

- `TransactionStore.baseCurrency` — `var` without `@ObservationIgnored`, because currency change must trigger UI recalc
- `DepositsViewModel.balanceCoordinator` — `var?` without `@ObservationIgnored`, assigned after `init` (late injection)

### Reading `@Observable` Collections

⚠️ Reading `.count` / `.isEmpty` / `dict[key]` on an `@Observable` collection subscribes the body to the whole collection. For hot paths over 19k transactions, maintain a separate Observable scalar mirror (e.g. `TransactionStore.transactionsCount`) and read that instead.

### Making `@Observable` Property Reactive

To make a property reactive: remove `@ObservationIgnored`, change to `private(set) var`; in the observing View add `.onChange(of: vm.property) { ... }`.

## Reference

For the original audit (2026-03-12) see archive:
- `docs/archive/CORE_DATA_AUDIT_2026_03_12.md` (23 fixes across 4 severity levels)
- `docs/archive/SWIFT_CONCURRENCY_AUDIT_2026_03_12.md` (527→0 warnings)
