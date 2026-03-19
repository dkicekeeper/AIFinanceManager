# План миграции на Core Data

## 📊 Текущее состояние

### Хранилище данных
- **UserDefaults** - все данные хранятся как JSON
- **Проблемы**:
  - Синхронная загрузка всех данных при старте
  - Нет встроенной пагинации
  - Нет индексов на уровне БД
  - Большой объем данных в памяти (~19000+ транзакций)
  - Нет атомарных операций
  - Нет миграционной поддержки

### Основные модели данных

| Модель | Количество записей | Размер | Критичность |
|--------|-------------------|--------|-------------|
| Transaction | 19000+ | ~10-15 MB | 🔴 Критично |
| Account | ~10 | <1 MB | 🟡 Средне |
| RecurringSeries | ~50 | <1 MB | 🟢 Низко |
| RecurringOccurrence | ~500 | ~2 MB | 🟡 Средне |
| CustomCategory | ~30 | <1 MB | 🟢 Низко |
| CategoryRule | ~100 | <1 MB | 🟢 Низко |
| Subcategory | ~50 | <1 MB | 🟢 Низко |

**Итого**: ~15-20 MB данных, 20000+ объектов

---

## 🎯 Цели миграции

### Производительность
- ✅ Асинхронная загрузка данных
- ✅ Встроенная пагинация через NSFetchRequest
- ✅ Индексы на часто используемых полях
- ✅ Фоновые контексты для тяжелых операций
- ✅ Автоматическое управление памятью (faulting)

### Функциональность
- ✅ Связи между сущностями (relationships)
- ✅ Каскадное удаление
- ✅ Встроенная валидация
- ✅ Версионирование модели и миграции
- ✅ Conflict resolution для concurrent changes

### Ожидаемые улучшения
- **Запуск приложения**: От <0.5 сек до **<0.2 сек** (только создание контекста)
- **Открытие HistoryView**: **мгновенно** (загружается только первая страница)
- **Фильтрация**: **в 10-100x быстрее** (индексы БД)
- **Память**: **-80%** (faulting + pagination)
- **CSV Import**: **в 2-3x быстрее** (batch inserts)

---

## 📐 Core Data Модель

### 1. TransactionEntity

```swift
@objc(TransactionEntity)
public class TransactionEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var date: Date  // ИЗМЕНЕНО: Date вместо String
    @NSManaged public var descriptionText: String  // 'description' - reserved
    @NSManaged public var amount: Double
    @NSManaged public var currency: String
    @NSManaged public var convertedAmount: NSNumber?  // Optional
    @NSManaged public var type: String  // Enum as String
    @NSManaged public var category: String
    @NSManaged public var subcategory: String?
    @NSManaged public var createdAt: Date
    
    // Relationships
    @NSManaged public var account: AccountEntity?
    @NSManaged public var targetAccount: AccountEntity?
    @NSManaged public var recurringSeries: RecurringSeriesEntity?
    @NSManaged public var recurringOccurrence: RecurringOccurrenceEntity?
    @NSManaged public var subcategoryLinks: NSSet?  // TransactionSubcategoryLinkEntity
}

// Indexes:
// - id (unique)
// - date (compound with type)
// - type
// - category
// - account.id
```

### 2. AccountEntity

```swift
@objc(AccountEntity)
public class AccountEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var balance: Double
    @NSManaged public var currency: String
    @NSManaged public var isDeposit: Bool
    @NSManaged public var bankName: String?
    @NSManaged public var logo: String?  // BankLogo as String
    @NSManaged public var createdAt: Date
    
    // Relationships
    @NSManaged public var transactions: NSSet?  // TransactionEntity
    @NSManaged public var targetTransactions: NSSet?  // TransactionEntity (inverse)
    @NSManaged public var recurringSeries: NSSet?  // RecurringSeriesEntity
}

// Indexes:
// - id (unique)
// - name
```

### 3. RecurringSeriesEntity

```swift
@objc(RecurringSeriesEntity)
public class RecurringSeriesEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var isActive: Bool
    @NSManaged public var amount: NSDecimalNumber
    @NSManaged public var currency: String
    @NSManaged public var category: String
    @NSManaged public var subcategory: String?
    @NSManaged public var descriptionText: String
    @NSManaged public var frequency: String  // Enum as String
    @NSManaged public var startDate: Date
    @NSManaged public var lastGeneratedDate: Date?
    @NSManaged public var kind: String  // generic/subscription
    @NSManaged public var brandLogo: String?
    @NSManaged public var brandId: String?
    @NSManaged public var status: String?  // SubscriptionStatus
    
    // Relationships
    @NSManaged public var account: AccountEntity?
    @NSManaged public var targetAccount: AccountEntity?
    @NSManaged public var transactions: NSSet?  // TransactionEntity
    @NSManaged public var occurrences: NSSet?  // RecurringOccurrenceEntity
}

// Indexes:
// - id (unique)
// - isActive
// - kind
```

### 4. RecurringOccurrenceEntity

```swift
@objc(RecurringOccurrenceEntity)
public class RecurringOccurrenceEntity: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var occurrenceDate: Date
    
    // Relationships
    @NSManaged public var series: RecurringSeriesEntity
    @NSManaged public var transaction: TransactionEntity
}

// Indexes:
// - id (unique)
// - occurrenceDate
```

### 5. CustomCategoryEntity, CategoryRuleEntity, SubcategoryEntity
(Аналогично, с соответствующими полями и relationships)

---

## 🚀 План реализации

### Фаза 1: Подготовка (1-2 дня)

#### 1.1. Создание Core Data модели
- [ ] Создать `.xcdatamodeld` файл
- [ ] Определить все Entity с атрибутами
- [ ] Настроить Relationships
- [ ] Настроить Indexes
- [ ] Настроить Delete Rules (Cascade, Nullify, Deny)

#### 1.2. Генерация NSManagedObject классов
```bash
# Автоматическая генерация в Xcode
Editor > Create NSManagedObject Subclass...
```

#### 1.3. Создание CoreDataStack
```swift
// CoreDataStack.swift
class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AIFinanceManager")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        
        // Automatic merge from parent context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }
    
    func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
```

---

### Фаза 2: Создание Repository слоя (2-3 дня)

#### 2.1. Протокол CoreDataRepository
```swift
protocol CoreDataRepositoryProtocol {
    // Transactions
    func fetchTransactions(
        predicate: NSPredicate?,
        sortDescriptors: [NSSortDescriptor]?,
        limit: Int?,
        offset: Int?
    ) async throws -> [TransactionEntity]
    
    func fetchTransactionsPublisher(
        predicate: NSPredicate?,
        sortDescriptors: [NSSortDescriptor]?
    ) -> AnyPublisher<[TransactionEntity], Error>
    
    func saveTransaction(_ transaction: Transaction) async throws
    func saveTransactions(_ transactions: [Transaction]) async throws
    func deleteTransaction(id: String) async throws
    func updateTransaction(id: String, updates: [String: Any]) async throws
    
    // Accounts
    func fetchAccounts() async throws -> [AccountEntity]
    func saveAccount(_ account: Account) async throws
    func deleteAccount(id: String) async throws
    
    // Recurring
    func fetchRecurringSeries(activeOnly: Bool) async throws -> [RecurringSeriesEntity]
    func saveRecurringSeries(_ series: RecurringSeries) async throws
    
    // Aggregate queries
    func calculateAccountBalance(accountId: String, upToDate: Date) async throws -> Double
    func fetchTransactionsSummary(
        startDate: Date,
        endDate: Date,
        accountIds: [String]?
    ) async throws -> (income: Double, expense: Double)
}
```

#### 2.2. Реализация CoreDataRepository
```swift
class CoreDataRepository: CoreDataRepositoryProtocol {
    private let stack = CoreDataStack.shared
    
    func fetchTransactions(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [TransactionEntity] {
        let context = stack.viewContext
        
        return try await context.perform {
            let request = TransactionEntity.fetchRequest()
            request.predicate = predicate
            request.sortDescriptors = sortDescriptors ?? [
                NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)
            ]
            if let limit = limit {
                request.fetchLimit = limit
            }
            if let offset = offset {
                request.fetchOffset = offset
            }
            
            return try context.fetch(request)
        }
    }
    
    // Batch insert для CSV импорта (ОЧЕНЬ быстро)
    func saveTransactions(_ transactions: [Transaction]) async throws {
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for transaction in transactions {
                let entity = TransactionEntity(context: context)
                entity.id = transaction.id
                entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
                entity.descriptionText = transaction.description
                entity.amount = transaction.amount
                entity.currency = transaction.currency
                entity.convertedAmount = transaction.convertedAmount as NSNumber?
                entity.type = transaction.type.rawValue
                entity.category = transaction.category
                entity.subcategory = transaction.subcategory
                entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
                
                // Set relationships
                if let accountId = transaction.accountId {
                    entity.account = try self.fetchAccount(id: accountId, context: context)
                }
            }
            
            try context.save()
        }
    }
}
```

---

### Фаза 3: Адаптация ViewModel слоя (3-4 дня)

#### 3.1. Обновить TransactionsViewModel
```swift
@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var transactions: [TransactionEntity] = []
    @Published var isLoading = false
    
    private let repository: CoreDataRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(repository: CoreDataRepositoryProtocol = CoreDataRepository()) {
        self.repository = repository
    }
    
    // Загрузка с пагинацией
    func loadTransactions(
        page: Int = 0,
        pageSize: Int = 50,
        filters: TransactionFilters? = nil
    ) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let predicate = buildPredicate(from: filters)
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)
            ]
            
            let results = try await repository.fetchTransactions(
                predicate: predicate,
                sortDescriptors: sortDescriptors,
                limit: pageSize,
                offset: page * pageSize
            )
            
            if page == 0 {
                transactions = results
            } else {
                transactions.append(contentsOf: results)
            }
        } catch {
            print("Error loading transactions: \(error)")
        }
    }
    
    // Real-time updates через Publisher
    func observeTransactions(filters: TransactionFilters? = nil) {
        let predicate = buildPredicate(from: filters)
        
        repository.fetchTransactionsPublisher(
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)]
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak self] transactions in
                self?.transactions = transactions
            }
        )
        .store(in: &cancellables)
    }
}
```

#### 3.2. Использование NSFetchedResultsController
```swift
// Для HistoryView - автоматические обновления
class TransactionsFRC: NSObject, ObservableObject {
    @Published var transactions: [TransactionEntity] = []
    
    private var fetchedResultsController: NSFetchedResultsController<TransactionEntity>
    
    init(predicate: NSPredicate? = nil) {
        let request = TransactionEntity.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \TransactionEntity.date, ascending: false)
        ]
        request.fetchBatchSize = 50
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: CoreDataStack.shared.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        super.init()
        
        fetchedResultsController.delegate = self
        try? fetchedResultsController.performFetch()
        transactions = fetchedResultsController.fetchedObjects ?? []
    }
}

extension TransactionsFRC: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        transactions = fetchedResultsController.fetchedObjects ?? []
    }
}
```

---

### Фаза 4: Миграция данных (2-3 дня)

#### 4.1. Создание миграционного сервиса
```swift
class MigrationService {
    private let userDefaultsRepo = UserDefaultsRepository()
    private let coreDataRepo = CoreDataRepository()
    
    func migrateFromUserDefaults() async throws {
        print("🔄 Starting migration from UserDefaults to Core Data")
        
        // 1. Check if migration needed
        guard needsMigration() else {
            print("✅ Migration not needed")
            return
        }
        
        // 2. Migrate Accounts (first, as transactions depend on them)
        let accounts = userDefaultsRepo.loadAccounts()
        for account in accounts {
            try await coreDataRepo.saveAccount(account)
        }
        print("✅ Migrated \(accounts.count) accounts")
        
        // 3. Migrate Transactions (batch insert for speed)
        let transactions = userDefaultsRepo.loadTransactions()
        try await coreDataRepo.saveTransactions(transactions)
        print("✅ Migrated \(transactions.count) transactions")
        
        // 4. Migrate RecurringSeries
        let series = userDefaultsRepo.loadRecurringSeries()
        for s in series {
            try await coreDataRepo.saveRecurringSeries(s)
        }
        print("✅ Migrated \(series.count) recurring series")
        
        // 5. Mark migration complete
        UserDefaults.standard.set(true, forKey: "CoreDataMigrationCompleted")
        print("🎉 Migration completed successfully!")
    }
    
    private func needsMigration() -> Bool {
        !UserDefaults.standard.bool(forKey: "CoreDataMigrationCompleted")
    }
}
```

#### 4.2. Запуск миграции при первом старте
```swift
// В AppCoordinator.initialize()
func initialize() async {
    // Run migration if needed (one-time)
    if !UserDefaults.standard.bool(forKey: "CoreDataMigrationCompleted") {
        do {
            try await MigrationService().migrateFromUserDefaults()
        } catch {
            print("❌ Migration failed: \(error)")
            // Handle error (show alert, retry, etc.)
        }
    }
    
    // Load data from Core Data
    await transactionsViewModel.loadTransactions()
}
```

---

### Фаза 5: Оптимизация и тестирование (2-3 дня)

#### 5.1. Настройка индексов
```swift
// В .xcdatamodeld
// TransactionEntity:
// - Compound index: (date, type)
// - Index: category
// - Index: account.id

// AccountEntity:
// - Index: name
```

#### 5.2. Batch операции для CSV импорта
```swift
func importCSV(_ file: CSVFile) async throws {
    let context = CoreDataStack.shared.newBackgroundContext()
    
    try await context.perform {
        // Use batch insert for maximum performance
        let batchInsert = NSBatchInsertRequest(
            entity: TransactionEntity.entity(),
            objects: file.rows.map { row in
                [
                    "id": UUID().uuidString,
                    "date": DateFormatters.dateFormatter.date(from: row.date) ?? Date(),
                    "descriptionText": row.description,
                    "amount": row.amount,
                    "currency": row.currency,
                    "type": row.type.rawValue,
                    "category": row.category,
                    "createdAt": Date()
                ]
            }
        )
        
        try context.execute(batchInsert)
    }
}
```

#### 5.3. Prefetching relationships
```swift
// Для избежания N+1 queries
request.relationshipKeyPathsForPrefetching = ["account", "recurringSeries"]
```

#### 5.4. Faulting и memory management
```swift
// Автоматически работает в Core Data
// Только загруженные данные в памяти
// Можно настроить:
context.stalenessInterval = 10.0  // Refresh every 10 seconds
request.returnsObjectsAsFaults = true  // Default
```

---

## 📊 Ожидаемые метрики

### До миграции (UserDefaults):
- Запуск: ~0.5 сек (загрузка 20MB JSON)
- Открытие HistoryView: ~0.5 сек (фильтрация + группировка)
- Фильтрация: ~50-100ms (in-memory)
- Память: ~80-100 MB
- CSV Import (19000 транзакций): ~5-10 секунд

### После миграции (Core Data):
- Запуск: **~0.1 сек** (только инициализация контекста)
- Открытие HistoryView: **~0.05 сек** (загрузка первой страницы)
- Фильтрация: **~5-10ms** (SQL индексы)
- Память: **~20-30 MB** (faulting + pagination)
- CSV Import (19000 транзакций): **~2-3 секунды** (batch insert)

### Улучшения:
- **Запуск**: 5x быстрее
- **HistoryView**: 10x быстрее
- **Фильтрация**: 10x быстрее
- **Память**: -70%
- **CSV Import**: 2-3x быстрее

---

## ⚠️ Риски и митигация

### Риск 1: Сложность миграции
- **Митигация**: Поэтапная миграция, тестирование на копии данных
- **Rollback**: Сохранить UserDefaults backup на случай проблем

### Риск 2: Производительность при больших объемах
- **Митигация**: Batch операции, правильные индексы, prefetching
- **Мониторинг**: Instruments для профилирования

### Риск 3: Concurrent modifications
- **Митигация**: Правильный merge policy, фоновые контексты
- **Тестирование**: Unit tests для concurrent scenarios

### Риск 4: Обратная совместимость
- **Митигация**: Версионирование Core Data модели, lightweight migrations
- **План**: Поддержка model versions для будущих изменений

---

## 📅 Timeline

| Фаза | Задачи | Время | Статус |
|------|--------|-------|--------|
| 1 | Создание Core Data модели | 1-2 дня | ⏳ To Do |
| 2 | Repository слой | 2-3 дня | ⏳ To Do |
| 3 | Адаптация ViewModels | 3-4 дня | ⏳ To Do |
| 4 | Миграция данных | 2-3 дня | ⏳ To Do |
| 5 | Оптимизация и тестирование | 2-3 дня | ⏳ To Do |

**Итого**: 10-15 дней

---

## 🎯 Критерии успеха

- [ ] Все данные мигрированы без потерь
- [ ] Запуск приложения <0.2 сек
- [ ] Открытие HistoryView <0.1 сек
- [ ] Фильтрация <10ms
- [ ] Использование памяти <30 MB
- [ ] CSV Import 19000 транзакций <3 сек
- [ ] Все существующие функции работают
- [ ] Unit tests покрывают 80%+ кода
- [ ] Нет memory leaks
- [ ] Нет crashes

---

## 📚 Ресурсы

- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)
- [NSFetchedResultsController](https://developer.apple.com/documentation/coredata/nsfetchedresultscontroller)
- [Core Data Performance](https://developer.apple.com/videos/play/wwdc2018/224/)
- [Batch Operations](https://developer.apple.com/documentation/coredata/loading_and_displaying_a_large_data_feed)

---

## 🚦 Начало работы

Готовы начать? Следующий шаг:

1. ✅ Создать Core Data Model (.xcdatamodeld)
2. ✅ Определить первую Entity (TransactionEntity)
3. ✅ Создать CoreDataStack
4. ✅ Протестировать на небольшом dataset

**Начать с Фазы 1?** (Y/N)
