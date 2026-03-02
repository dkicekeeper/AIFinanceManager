# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-02)

**Core value:** Точный учёт финансов с мгновенным откликом — приложение не должно терять данные, зависать или давать неверные цифры.
**Current focus:** Phase 1 — Safety & Cleanup

## Current Position

Phase: 1 of 4 (Safety & Cleanup)
Plan: 2 of 3 in current phase
Status: In progress
Last activity: 2026-03-02 — Completed 01-02 (DateFormatter fix + tombstone deletion)

Progress: [██░░░░░░░░] 10%

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: 4 min
- Total execution time: 0.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Safety & Cleanup | 1 | 4 min | 4 min |

**Recent Trend:**
- Last 5 plans: 01-02 (4 min)
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full log. Active decisions affecting current work:

- Delete `RecurringTransactionService` entirely rather than partial fix (deadlock risk too high for targeted fix)
- `UnifiedTransactionCache`: replace incomplete prefix invalidation with full invalidation (simpler, safe enough for current load)
- `TransactionStore`: extract only `RecurringStore` this milestone; full split deferred (too risky without tests)
- CoreData file protection: `.complete` (financial data; iOS enforces at locked screen)
- Use `@MainActor private static let` (not `nonisolated(unsafe)`) for DateFormatter on @MainActor classes — matches CLAUDE.md rule
- Delete tombstone files immediately — no live code referenced them; only historical comments remained

### Pending Todos

None.

### Blockers/Concerns

- Phase 3 (PERF-02 RecurringStore extract) must not start until Phase 1 SAFE-01 is complete; extracting recurring while the deprecated service still exists creates two competing sources of truth
- DATA-01 (CoreData migration) requires verifying against real device with old app version installed; emulator-only testing is insufficient

## Session Continuity

Last session: 2026-03-02
Stopped at: Completed 01-02-PLAN.md — DateFormatter race fix + tombstone deletion; next is 01-03-PLAN.md
Resume file: None
