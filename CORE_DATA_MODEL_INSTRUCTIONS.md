# Инструкции: Создание Core Data модели в Xcode

## Шаг 1: Создание Data Model файла

1. **Открыть Xcode проект** `AIFinanceManager.xcodeproj`

2. **Создать новый файл**:
   - File → New → File... (⌘N)
   - В разделе "Core Data" выбрать **"Data Model"**
   - Имя файла: `AIFinanceManager`
   - Сохранить в: `AIFinanceManager/CoreData/`
   - ✅ Убедиться, что файл добавлен в target "AIFinanceManager"

Это создаст файл `AIFinanceManager.xcdatamodeld`

---

## Шаг 2: Создание Entity "TransactionEntity"

### 2.1. Добавить Entity

1. Открыть `AIFinanceManager.xcdatamodeld`
2. Нажать **"Add Entity"** (кнопка + внизу)
3. Назвать: `TransactionEntity`
4. В инспекторе справа:
   - **Class**: `TransactionEntity`
   - **Module**: `AIFinanceManager`
   - **Codegen**: **Manual/None** (мы создадим классы сами)

### 2.2. Добавить Attributes

Нажать **"+"** в секции **Attributes** и добавить:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `date` | Date | ❌ No | - |
| `descriptionText` | String | ❌ No | "" |
| `amount` | Double | ❌ No | 0 |
| `currency` | String | ❌ No | "KZT" |
| `convertedAmount` | Double | ✅ Yes | - |
| `type` | String | ❌ No | - |
| `category` | String | ❌ No | - |
| `subcategory` | String | ✅ Yes | - |
| `createdAt` | Date | ❌ No | - |

**Важно**: Не используйте название `description` - это зарезервированное слово в NSObject!

### 2.3. Настроить индексы (опционально)

**Если в вашей версии Xcode есть секция "Indexes"** в инспекторе справа:
1. Выбрать `TransactionEntity`
2. В инспекторе справа найти секцию **"Indexes"**
3. Добавить составной индекс:
   - Нажать **"+"**
   - Имя: `dateTypeIndex`
   - Elements: `date`, `type`

**Если секции "Indexes" нет** - не проблема! Индексы можно добавить программно позже, или Core Data автоматически оптимизирует запросы. Продолжаем без индексов.

---

## Шаг 3: Создание Entity "AccountEntity"

### 3.1. Добавить Entity

1. Нажать **"Add Entity"**
2. Назвать: `AccountEntity`
3. Настроить:
   - **Class**: `AccountEntity`
   - **Codegen**: **Manual/None**

### 3.2. Добавить Attributes

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `name` | String | ❌ No | - |
| `balance` | Double | ❌ No | 0 |
| `currency` | String | ❌ No | "KZT" |
| `isDeposit` | Boolean | ❌ No | false |
| `bankName` | String | ✅ Yes | - |
| `logo` | String | ✅ Yes | - |
| `createdAt` | Date | ❌ No | - |

---

## Шаг 4: Создание Relationships между Entity

### 4.1. Relationship: Transaction → Account

1. Выбрать `TransactionEntity`
2. В секции **Relationships** нажать **"+"**
3. Настроить:
   - **Name**: `account`
   - **Destination**: `AccountEntity`
   - **Inverse**: `transactions` (создастся автоматически)
   - **Type**: To One
   - **Delete Rule**: Nullify
   - **Optional**: ✅ Yes

### 4.2. Relationship: Transaction → Target Account

1. В `TransactionEntity` добавить еще один relationship:
   - **Name**: `targetAccount`
   - **Destination**: `AccountEntity`
   - **Inverse**: `targetTransactions`
   - **Type**: To One
   - **Delete Rule**: Nullify
   - **Optional**: ✅ Yes

### 4.3. Relationship: Account → Transactions

1. Выбрать `AccountEntity`
2. Проверить, что автоматически созданы relationships:
   - `transactions` (To Many, inverse: `account`)
   - `targetTransactions` (To Many, inverse: `targetAccount`)
3. Настроить **Delete Rule** для обоих:
   - **Delete Rule**: Nullify (транзакции останутся при удалении счета)

---

## Шаг 5: Создание Entity "RecurringSeriesEntity"

### 5.1. Добавить Entity

1. Нажать **"Add Entity"**
2. Назвать: `RecurringSeriesEntity`
3. **Codegen**: **Manual/None**

### 5.2. Добавить Attributes

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `isActive` | Boolean | ❌ No | true |
| `amount` | Decimal | ❌ No | 0 |
| `currency` | String | ❌ No | "KZT" |
| `category` | String | ❌ No | - |
| `subcategory` | String | ✅ Yes | - |
| `descriptionText` | String | ❌ No | "" |
| `frequency` | String | ❌ No | - |
| `startDate` | Date | ❌ No | - |
| `lastGeneratedDate` | Date | ✅ Yes | - |
| `kind` | String | ❌ No | "generic" |
| `brandLogo` | String | ✅ Yes | - |
| `brandId` | String | ✅ Yes | - |
| `status` | String | ✅ Yes | - |

### 5.3. Добавить Relationships

1. **RecurringSeries → Account**:
   - Name: `account`
   - Destination: `AccountEntity`
   - Type: To One
   - Optional: ✅ Yes

2. **RecurringSeries → Transactions**:
   - Name: `transactions`
   - Destination: `TransactionEntity`
   - Type: To Many
   - Optional: ✅ Yes
   - Inverse: `recurringSeries` (добавить в TransactionEntity)

---

## Шаг 6: Создание остальных Entities (опционально, можно позже)

> **Примечание**: Эти Entity можно создать позже, когда они понадобятся. Если вы хотите создать их сейчас, следуйте инструкциям ниже.

### 6.1. Создание Entity "CustomCategoryEntity"

1. **Добавить Entity**:
   - Нажать **"Add Entity"** (кнопка + внизу)
   - Назвать: `CustomCategoryEntity`
   - В инспекторе справа:
     - **Class**: `CustomCategoryEntity`
     - **Module**: `AIFinanceManager`
     - **Codegen**: **Manual/None**

2. **Добавить Attributes**:
   - Нажать **"+"** в секции **Attributes** и добавить:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `name` | String | ❌ No | - |
| `type` | String | ❌ No | - |
| `iconName` | String | ✅ Yes | - |
| `colorHex` | String | ✅ Yes | - |

---

### 6.2. Создание Entity "CategoryRuleEntity"

1. **Добавить Entity**:
   - Нажать **"Add Entity"**
   - Назвать: `CategoryRuleEntity`
   - В инспекторе справа:
     - **Class**: `CategoryRuleEntity`
     - **Module**: `AIFinanceManager`
     - **Codegen**: **Manual/None**

2. **Добавить Attributes**:
   - Нажать **"+"** в секции **Attributes** и добавить:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `pattern` | String | ❌ No | - |
| `category` | String | ❌ No | - |
| `isEnabled` | Boolean | ❌ No | true |

---

### 6.3. Создание Entity "SubcategoryEntity"

1. **Добавить Entity**:
   - Нажать **"Add Entity"**
   - Назвать: `SubcategoryEntity`
   - В инспекторе справа:
     - **Class**: `SubcategoryEntity`
     - **Module**: `AIFinanceManager`
     - **Codegen**: **Manual/None**

2. **Добавить Attributes**:
   - Нажать **"+"** в секции **Attributes** и добавить:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| `id` | String | ❌ No | - |
| `name` | String | ❌ No | - |
| `iconName` | String | ✅ Yes | - |

---

### 6.4. Настройка Relationships (если нужно)

Если эти Entity должны быть связаны с другими:

- **CustomCategoryEntity ↔ TransactionEntity**: 
  - Можно добавить relationship `transactions` (To Many) в `CustomCategoryEntity`
  - Или использовать только строковое поле `category` в `TransactionEntity` (текущий подход)

- **CategoryRuleEntity**: 
  - Обычно не требует relationships, это правила для автоматической категоризации

- **SubcategoryEntity ↔ TransactionEntity**:
  - Можно добавить relationship `transactions` (To Many) в `SubcategoryEntity`
  - Или использовать только строковое поле `subcategory` в `TransactionEntity` (текущий подход)

> **Рекомендация**: Если вы не уверены, нужны ли relationships, оставьте их как строковые поля в `TransactionEntity` (как сейчас). Relationships можно добавить позже при необходимости.

---

## Шаг 7: Генерация NSManagedObject классов

### 7.1. Автоматическая генерация через Xcode

1. Выбрать все Entity (⌘+Click)
2. Editor → Create NSManagedObject Subclass...
3. Выбрать модель: `AIFinanceManager`
4. Выбрать все Entity
5. Сохранить в: `AIFinanceManager/CoreData/Entities/`
6. ✅ Убедиться, что в target "AIFinanceManager"

Xcode создаст файлы:
- `TransactionEntity+CoreDataClass.swift`
- `TransactionEntity+CoreDataProperties.swift`
- `AccountEntity+CoreDataClass.swift`
- `AccountEntity+CoreDataProperties.swift`
- И т.д.

### 7.2. Добавить удобные методы в классы

В `TransactionEntity+CoreDataClass.swift`:

```swift
extension TransactionEntity {
    /// Convert to domain model
    func toTransaction() -> Transaction {
        return Transaction(
            id: id ?? "",
            date: DateFormatters.dateFormatter.string(from: date ?? Date()),
            description: descriptionText ?? "",
            amount: amount,
            currency: currency ?? "KZT",
            convertedAmount: convertedAmount as? Double,
            type: TransactionType(rawValue: type ?? "expense") ?? .expense,
            category: category ?? "",
            subcategory: subcategory,
            accountId: account?.id,
            targetAccountId: targetAccount?.id,
            recurringSeriesId: recurringSeries?.id,
            recurringOccurrenceId: nil,
            createdAt: createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        )
    }
    
    /// Create from domain model
    static func from(_ transaction: Transaction, context: NSManagedObjectContext) -> TransactionEntity {
        let entity = TransactionEntity(context: context)
        entity.id = transaction.id
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date)
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount as NSNumber?
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        return entity
    }
}
```

---

## Шаг 8: Проверка модели

### 8.1. Проверить в редакторе

1. Открыть `AIFinanceManager.xcdatamodeld`
2. Убедиться, что:
   - ✅ Все Entity созданы
   - ✅ Все Attributes имеют правильные типы
   - ✅ Relationships настроены корректно
   - ✅ Indexes добавлены
   - ✅ Delete Rules настроены

### 8.2. Собрать проект

```bash
# В терминале или в Xcode (⌘+B)
xcodebuild -scheme AIFinanceManager -configuration Debug
```

Если есть ошибки - исправить.

---

## Шаг 9: Тестирование CoreDataStack

### 9.1. Создать простой тест

Добавить в `AppCoordinator.swift`:

```swift
// TEMPORARY TEST CODE
func testCoreData() {
    let stack = CoreDataStack.shared
    let context = stack.viewContext
    
    // Create test transaction
    let transaction = TransactionEntity(context: context)
    transaction.id = UUID().uuidString
    transaction.date = Date()
    transaction.descriptionText = "Test Transaction"
    transaction.amount = 1000.0
    transaction.currency = "KZT"
    transaction.type = "expense"
    transaction.category = "Food"
    transaction.createdAt = Date()
    
    // Save
    do {
        try stack.saveContextSync(context)
        print("✅ Test transaction saved!")
        
        // Fetch
        let request = TransactionEntity.fetchRequest()
        let results = try context.fetch(request)
        print("✅ Fetched \(results.count) transactions")
        
        // Delete test data
        for entity in results {
            context.delete(entity)
        }
        try stack.saveContextSync(context)
        print("✅ Test data deleted")
        
    } catch {
        print("❌ Test failed: \(error)")
    }
}
```

Вызвать из `initialize()`:

```swift
func initialize() async {
    #if DEBUG
    testCoreData()
    #endif
    
    // ... rest of initialization
}
```

---

## ✅ Checklist

- [x] Создан файл `AIFinanceManager.xcdatamodeld`
- [x] Создана Entity `TransactionEntity` со всеми attributes
- [x] Создана Entity `AccountEntity` со всеми attributes
- [x] Создана Entity `RecurringSeriesEntity` со всеми attributes
- [x] Настроены Relationships между entities
- [ ] Добавлены Indexes для производительности (опционально, можно добавить позже)
- [x] Сгенерированы NSManagedObject классы
- [x] Добавлены удобные методы (toTransaction, toAccount, from)
- [x] CoreDataStack.swift добавлен в проект
- [x] Проект собирается без ошибок (⌘+B)
- [x] Тестовый код работает ✅

---

## 🎯 Следующий шаг

После завершения этого шага у нас будет:
- ✅ Core Data модель
- ✅ CoreDataStack для управления
- ✅ Базовые Entity классы
- ✅ Методы конвертации между Entity и Domain моделями
- ✅ Рабочий тест Core Data

**✅ Фаза 1 завершена!**

**Готовы к Фазе 2 (Repository слой)?**

Следующие шаги:
1. Создать `CoreDataRepository` который реализует `DataRepositoryProtocol`
2. Реализовать методы для работы с TransactionEntity, AccountEntity, RecurringSeriesEntity
3. Добавить миграцию данных из UserDefaults в Core Data
4. Обновить ViewModels для использования нового Repository

---

## 💡 Полезные советы

### Viewing Core Data in Xcode

1. Run app в симуляторе/устройстве
2. Debug → View Debugging → View Model
3. Можно посмотреть все Entity и relationships

### SQLite файл location

```bash
# Найти файл базы данных
~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Library/Application Support/

# Открыть в DB Browser for SQLite
open -a "DB Browser for SQLite" AIFinanceManager.sqlite
```

### Performance Tips

- ✅ Используйте batch операции для множественных вставок
- ✅ Используйте фоновые контексты для тяжелых операций
- ✅ Используйте `fetchBatchSize` для больших запросов
- ✅ Используйте `relationshipKeyPathsForPrefetching` чтобы избежать N+1
- ✅ Не загружайте все данные в память - используйте pagination

---

## 📚 Ресурсы

- [Core Data Model Editor Help](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreDataVersioning/Articles/Introduction.html)
- [NSManagedObject Guide](https://developer.apple.com/documentation/coredata/nsmanagedobject)
- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)
