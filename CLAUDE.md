# AIFinanceManager - Project Guide for Claude

## Project Overview

AIFinanceManager is a native iOS finance management application built with SwiftUI and CoreData. The app helps users track accounts, transactions, budgets, deposits, and recurring payments with a modern, user-friendly interface.

**Tech Stack:**
- SwiftUI (iOS 26+ with Liquid Glass adoption)
- Swift 6.0+ with strict concurrency
- CoreData for persistence
- Observation framework (@Observable)
- MVVM + Coordinator architecture

## Project Structure

```
AIFinanceManager/
├── Models/              # CoreData entities and business models
├── ViewModels/          # Observable view models (@MainActor)
├── Views/               # SwiftUI views and components
├── Services/            # Business logic and data services
├── Repositories/        # Data access layer (CoreData)
├── Coordinators/        # Dependency injection and coordination
├── Stores/              # Single source of truth (Phase 7+)
└── Utils/               # Helper utilities and extensions
```

## Architecture Principles

### MVVM + Coordinator Pattern
- **Models**: CoreData entities representing domain objects
- **ViewModels**: @Observable classes marked @MainActor for UI state
- **Views**: SwiftUI views that observe ViewModels
- **Coordinators**: Manage dependencies and initialization (AppCoordinator)
- **Stores**: Single source of truth for specific domains (TransactionStore)

### Key Architectural Components

#### AppCoordinator
- Central dependency injection point
- Manages all ViewModels and their dependencies
- Located at: `AIFinanceManager/ViewModels/AppCoordinator.swift`
- Provides: Repository, all ViewModels, Stores, and Coordinators

#### TransactionStore (Phase 7+, Enhanced Phase 9)
- Single source of truth for transactions
- Handles subscriptions and recurring transactions
- Replaces multiple legacy services
- Event-driven architecture with TransactionStoreEvent

#### BalanceCoordinator (Phase 1-4)
- Single entry point for balance operations
- Manages balance calculation and caching
- Includes: Store, Engine, Queue, Cache

### Recent Refactoring Phases

**Phase 9** (Latest):
- Removed SubscriptionsViewModel - recurring operations moved to TransactionStore
- Removed RecurringTransactionCoordinator - operations consolidated
- Enhanced TransactionStore with recurring operations support

**Phase 7**: TransactionStore introduction
**Phase 1-4**: BalanceCoordinator foundation
**Phase 1**: Settings refactoring with SettingsViewModel

## Development Guidelines

### SwiftUI Best Practices
- Use modern SwiftUI APIs (iOS 26+ preferred)
- Follow strict concurrency (Swift 6.0+)
- Mark ViewModels with @Observable and @MainActor
- Use .onChange(of:) for reactive updates
- Adopt Liquid Glass design patterns where applicable

### State Management
- ViewModels are the source of truth for UI state
- Use @Bindable for two-way bindings
- Avoid @State in views for complex state - delegate to ViewModels
- Use Observation framework, not Combine publishers

### CoreData Usage
- All CoreData operations through DataRepositoryProtocol
- Repository pattern abstracts persistence layer
- Fetch requests should be optimized with predicates
- Use background contexts for heavy operations

### Code Style
- Clear, descriptive variable and function names
- Document complex logic with comments
- Use MARK: comments to organize code sections
- Follow Swift naming conventions (lowerCamelCase for properties/methods)

### Performance Considerations
- Log performance metrics with TransactionsViewModel+PerformanceLogging
- Use background tasks for expensive operations
- Cache frequently accessed data (see BalanceCoordinator cache)
- Optimize CoreData fetch requests with appropriate batch sizes

## Common Tasks

### Adding a New Feature
1. Create model (if needed) in Models/
2. Add service logic in Services/ or enhance existing Store
3. Create/update ViewModel in ViewModels/
4. Build SwiftUI view in Views/
5. Wire up dependencies in AppCoordinator

### Working with Transactions
- Use TransactionStore for all transaction operations
- Subscribe to TransactionStoreEvent for reactive updates
- Handle recurring transactions through TransactionStore
- Performance logging available via extension

### Working with Balance
- Use BalanceCoordinator as single entry point
- Balance operations are cached automatically
- Background queue handles expensive calculations

### UI Components
- Reusable components should be in Views/Components/
- Follow existing naming patterns (e.g., MenuPicker)
- Support both light and dark modes
- Test on multiple device sizes

## Testing

- Unit tests: `AIFinanceManagerTests/`
- UI tests: `AIFinanceManagerUITests/`
- Test ViewModels with mock repositories
- Test CoreData operations with in-memory stores

## Git Workflow

Current branch: `main`
- Commit messages should be descriptive and concise
- Follow conventional commits when possible
- Always review changes before committing
- Include co-author tag for AI assistance

## Important Files to Reference

- **AppCoordinator.swift**: Dependency injection and initialization
- **TransactionStore.swift**: Transaction and recurring operations
- **BalanceCoordinator.swift**: Balance calculation coordination
- **DataRepository.swift**: CoreData abstraction layer

## AI Assistant Instructions

When working with this project:

1. **Always read before editing**: Use Read tool to understand existing code
2. **Follow architecture**: Respect MVVM + Coordinator patterns
3. **Use existing patterns**: Check similar implementations before creating new ones
4. **Update AppCoordinator**: When adding new ViewModels or dependencies
5. **Maintain consistency**: Follow existing code style and conventions
6. **Performance first**: Consider performance implications of changes
7. **Test changes**: Verify builds and runs after modifications
8. **Document refactoring**: Update this file when architecture changes

### Preferred Tools
- Use SwiftUI Expert skill for SwiftUI-specific tasks
- Use Read/Edit tools for file operations (not Bash cat/sed)
- Use Grep for searching code patterns
- Use Glob for finding files by pattern

### Don't
- Don't create unnecessary abstractions
- Don't ignore existing architectural patterns
- Don't add features without understanding context
- Don't skip reading existing code before modifications
- Don't use Combine when Observation framework is preferred

## Questions?

When unsure about architecture decisions:
1. Check existing similar implementations
2. Review AppCoordinator for dependency patterns
3. Look at recent commits for refactoring context
4. Ask user for clarification on business requirements

---

**Last Updated**: 2026-02-15
**Project Status**: Active development
**iOS Target**: 26.0+
**Swift Version**: 6.0+
