//
//  DepositInterestService.swift
//  AIFinanceManager
//
//  Service for calculating deposit interest accrual and posting
//

import Foundation

enum DepositInterestService {
    
    // MARK: - Public Methods
    
    /// Рассчитывает проценты за период и обновляет информацию депозита
    /// Идемпотентный: можно вызывать многократно без дублирования транзакций
    static func reconcileDepositInterest(
        account: inout Account,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        guard var depositInfo = account.depositInfo else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Парсим даты
        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)
        
        // Если уже рассчитано до сегодня - ничего не делаем
        if lastCalcDateNormalized >= today {
            return
        }
        
        // Рассчитываем проценты за каждый день от lastCalcDate+1 до today
        var currentDate = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
        var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod
        
        while currentDate < today {
            // Получаем ставку для текущей даты
            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            
            // Базовая сумма для расчета (при капитализации - principalBalance, иначе тоже principalBalance)
            let baseAmount = depositInfo.principalBalance
            
            // Ежедневный процент: baseAmount * (annualRate/100) / 365
            let dailyInterest = baseAmount * (rate / 100) / 365
            totalAccrued += dailyInterest
            
            // Проверяем, нужно ли начислить проценты (если это день начисления)
            if shouldPostInterest(
                date: currentDate,
                postingDay: depositInfo.interestPostingDay,
                lastPostingMonth: depositInfo.lastInterestPostingMonth
            ) {
                // Начисляем проценты транзакцией
                let postingAmount = totalAccrued
                if postingAmount > 0 {
                    postInterest(
                        account: &account,
                        depositInfo: &depositInfo,
                        amount: postingAmount,
                        date: currentDate,
                        allTransactions: allTransactions,
                        onTransactionCreated: onTransactionCreated
                    )
                    totalAccrued = 0 // Сбрасываем накопленные проценты после начисления
                }
            }
            
            // Переходим к следующему дню
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Обновляем информацию депозита
        depositInfo.interestAccruedForCurrentPeriod = totalAccrued
        depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)
        
        // Обновляем balance счета на основе depositInfo
        updateAccountBalance(account: &account, depositInfo: depositInfo)
    }
    
    /// Добавляет новую ставку в историю
    static func addRateChange(depositInfo: inout DepositInfo, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        let rateChange = RateChange(effectiveFrom: effectiveFrom, annualRate: annualRate, note: note)
        depositInfo.interestRateHistory.append(rateChange)
        // Сортируем по дате (самые новые последние)
        depositInfo.interestRateHistory.sort { rate1, rate2 in
            guard let date1 = DateFormatters.dateFormatter.date(from: rate1.effectiveFrom),
                  let date2 = DateFormatters.dateFormatter.date(from: rate2.effectiveFrom) else {
                return false
            }
            return date1 < date2
        }
        // Обновляем текущую ставку
        depositInfo.interestRateAnnual = annualRate
    }
    
    /// Получает текущую ставку для депозита
    static func currentRate(depositInfo: DepositInfo) -> Decimal {
        return depositInfo.interestRateAnnual
    }
    
    /// Рассчитывает проценты на сегодня (без сохранения)
    static func calculateInterestToToday(depositInfo: DepositInfo) -> Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return depositInfo.interestAccruedForCurrentPeriod
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)
        
        var currentDate = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
        var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod
        
        while currentDate <= today {
            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            let baseAmount = depositInfo.principalBalance
            let dailyInterest = baseAmount * (rate / 100) / 365
            totalAccrued += dailyInterest
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return totalAccrued
    }
    
    /// Получает следующую дату начисления процентов
    static func nextPostingDate(depositInfo: DepositInfo) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let _ = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestPostingMonth) else {
            return nil
        }
        
        // Создаем дату начисления в текущем месяце
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = depositInfo.interestPostingDay
        
        // Если день больше количества дней в месяце, используем последний день
        if let date = calendar.date(from: components),
           let lastDayOfMonth = calendar.range(of: .day, in: .month, for: date)?.upperBound {
            if depositInfo.interestPostingDay >= lastDayOfMonth {
                components.day = lastDayOfMonth - 1
            }
        }
        
        guard let currentMonthPostingDate = calendar.date(from: components) else {
            return nil
        }
        
        // Если дата начисления в текущем месяце уже прошла, берем следующий месяц
        if currentMonthPostingDate <= today {
            var nextMonthComponents = calendar.dateComponents([.year, .month], from: today)
            nextMonthComponents.month = (nextMonthComponents.month ?? 0) + 1
            nextMonthComponents.day = depositInfo.interestPostingDay
            
            if let nextMonthDate = calendar.date(from: nextMonthComponents),
               let lastDayOfMonth = calendar.range(of: .day, in: .month, for: nextMonthDate)?.upperBound {
                if depositInfo.interestPostingDay >= lastDayOfMonth {
                    nextMonthComponents.day = lastDayOfMonth - 1
                }
            }
            
            return calendar.date(from: nextMonthComponents)
        }
        
        return currentMonthPostingDate
    }
    
    // MARK: - Private Methods
    
    /// Получает ставку для конкретной даты из истории
    private static func rateForDate(date: Date, history: [RateChange]) -> Decimal {
        let dateString = DateFormatters.dateFormatter.string(from: date)
        
        // Находим последнюю ставку, которая действует на эту дату
        var applicableRate: Decimal = 0
        for rateChange in history {
            if rateChange.effectiveFrom <= dateString {
                applicableRate = rateChange.annualRate
            } else {
                break
            }
        }
        
        // Если не нашли, используем первую ставку из истории
        return applicableRate > 0 ? applicableRate : (history.first?.annualRate ?? 0)
    }
    
    /// Проверяет, нужно ли начислить проценты в эту дату
    private static func shouldPostInterest(date: Date, postingDay: Int, lastPostingMonth: String) -> Bool {
        let calendar = Calendar.current
        let dateNormalized = calendar.startOfDay(for: date)
        
        // Получаем день месяца
        let day = calendar.component(.day, from: dateNormalized)
        
        // Проверяем, соответствует ли день месяца дню начисления
        var targetDay = postingDay
        if let lastDayOfMonth = calendar.range(of: .day, in: .month, for: dateNormalized)?.upperBound {
            if postingDay >= lastDayOfMonth {
                targetDay = lastDayOfMonth - 1
            }
        }
        
        guard day == targetDay else {
            return false
        }
        
        // Проверяем, что начисление за этот месяц еще не было
        guard let lastPostingDate = DateFormatters.dateFormatter.date(from: lastPostingMonth) else {
            return true
        }
        
        let lastPostingComponents = calendar.dateComponents([.year, .month], from: lastPostingDate)
        let currentComponents = calendar.dateComponents([.year, .month], from: dateNormalized)
        
        // Если месяц/год отличается - нужно начислить
        return lastPostingComponents.year != currentComponents.year ||
               lastPostingComponents.month != currentComponents.month
    }
    
    /// Начисляет проценты (создает транзакцию и обновляет баланс)
    private static func postInterest(
        account: inout Account,
        depositInfo: inout DepositInfo,
        amount: Decimal,
        date: Date,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        // Проверяем, что транзакция за этот месяц еще не создана (идемпотентность)
        let dateString = DateFormatters.dateFormatter.string(from: date)
        let calendar = Calendar.current
        let dateNormalized = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: dateNormalized)
        
        // Проверяем, есть ли уже транзакция начисления за этот месяц
        let monthStart = calendar.date(from: components)!
        let monthStartString = DateFormatters.dateFormatter.string(from: monthStart)
        
        let existingTransaction = allTransactions.first { transaction in
            transaction.accountId == account.id &&
            transaction.type == .depositInterestAccrual &&
            transaction.date >= monthStartString
        }
        
        if existingTransaction != nil {
            // Транзакция уже существует - не создаем дубль
            return
        }
        
        // Создаем транзакцию начисления процентов
        // Используем детерминированный ID для идемпотентности (depositId + month)
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
        let transactionId = generateDepositInterestTransactionID(
            depositId: account.id,
            month: monthStartString,
            amount: amountDouble,
            currency: account.currency
        )
        
        let transaction = Transaction(
            id: transactionId,
            date: dateString,
            description: "Начисление процентов",
            amount: amountDouble,
            currency: account.currency,
            convertedAmount: nil,
            type: .depositInterestAccrual,
            category: "Начисление процентов",
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil,
            accountName: account.name,
            targetAccountName: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )
        
        onTransactionCreated(transaction)
        
        // Обновляем баланс депозита
        if depositInfo.capitalizationEnabled {
            // Капитализация: увеличиваем principalBalance
            depositInfo.principalBalance += amount
        } else {
            // Без капитализации: накапливаем отдельно
            depositInfo.interestAccruedNotCapitalized += amount
        }
        
        // Обновляем дату последнего начисления (начало месяца)
        depositInfo.lastInterestPostingMonth = monthStartString
        
        // Обновляем информацию депозита в счете
        account.depositInfo = depositInfo
    }
    
    /// Обновляет баланс счета на основе информации депозита
    private static func updateAccountBalance(account: inout Account, depositInfo: DepositInfo) {
        var totalBalance: Decimal = depositInfo.principalBalance
        if !depositInfo.capitalizationEnabled {
            totalBalance += depositInfo.interestAccruedNotCapitalized
        }
        // Для отображения "проценты на сегодня" не добавляем interestAccruedForCurrentPeriod к балансу,
        // так как они еще не начислены. Баланс = principalBalance (+ начисленные проценты без капитализации)
        account.balance = NSDecimalNumber(decimal: totalBalance).doubleValue
    }
    
    /// Генерирует детерминированный ID для транзакции начисления процентов
    /// Основан на depositId + month, чтобы обеспечить идемпотентность
    private static func generateDepositInterestTransactionID(depositId: String, month: String, amount: Double, currency: String) -> String {
        let normalizedAmount = String(format: "%.2f", amount)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespaces).uppercased()
        let key = "deposit_interest|\(depositId)|\(month)|\(normalizedAmount)|\(normalizedCurrency)"
        
        var hasher = Hasher()
        hasher.combine(key)
        let raw = hasher.finalize()
        let unsigned = UInt64(bitPattern: Int64(raw))
        return String(format: "%016llx", unsigned)
    }
}
