//
//  SubscriptionCalendarView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

private struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
}

struct SubscriptionCalendarView: View {
    let subscriptions: [RecurringSeries]
    let baseCurrency: String
    @State private var currentMonthIndex: Int = 0
    @State private var monthlyTotals: [Int: Decimal] = [:] // monthIndex -> total in base currency
    private let calendar = Calendar.current

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = .current
        f.timeZone = TimeZone.current
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header

            // Static weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(AppTypography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(height: 20)
                }
            }

            GeometryReader { geometry in
                TabView(selection: $currentMonthIndex) {
                    ForEach(Array(allMonths.enumerated()), id: \.offset) { index, monthStart in
                        monthGrid(for: monthStart, availableHeight: geometry.size.height)
                            .tag(index)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: AppAnimation.slow), value: currentMonthIndex)
            }
            .frame(height: calculateCalendarHeight())
        }
        .glassCardStyle()
        .task {
            await calculateAllMonthTotals()
        }
        .onChange(of: subscriptions.count) { _, _ in
            Task {
                await calculateAllMonthTotals()
            }
        }
        .onChange(of: baseCurrency) { _, _ in
            Task {
                await calculateAllMonthTotals()
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    currentMonthIndex = 0
                }
            }) {
                Text(formatMonthYear(allMonths[currentMonthIndex]))
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            if let total = monthlyTotals[currentMonthIndex], total > 0 {
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: total).doubleValue,
                    currency: baseCurrency,
                    fontSize: AppTypography.bodyLarge,
                    color: AppColors.textPrimary
                )
            }
        }
        .animation(.easeInOut(duration: AppAnimation.standard), value: currentMonthIndex)
        .padding(.vertical, AppSpacing.sm)
    }

    private var allMonths: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return [today]
        }

        return (0..<12).compactMap { i in
            calendar.date(byAdding: .month, value: i, to: startOfMonth)
        }
    }

    private func monthGrid(for monthStart: Date, availableHeight: CGFloat) -> some View {
        // Days grid only (weekday headers are now static)
        LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
            let days = calendarDays(for: monthStart)
            ForEach(days) { day in
                if let date = day.date {
                    dateCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 60)
                }
            }
        }
        .padding(.top, AppSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func dateCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let occurrences = subscriptionsOnDate(date)

        return VStack(spacing: AppSpacing.xs) {
            Text("\(calendar.component(.day, from: date))")
                .font(isToday ? AppTypography.bodySmall.weight(.semibold) : AppTypography.bodySmall)
                .foregroundStyle(isToday ? AppColors.accent : AppColors.textPrimary)
                .frame(width: 32, height: 32)
                .background(isToday ? AppColors.accent.opacity(0.1) : Color.clear)
                .clipShape(Circle())
                .animation(.easeInOut(duration: AppAnimation.fast), value: isToday)

            // Logos
            if !occurrences.isEmpty {
                HStack(spacing: -AppSpacing.xs) {
                    ForEach(occurrences.prefix(3), id: \.id) { sub in
                        logoView(for: sub, size: AppIconSize.md)
                            .background(Circle().fill(AppColors.backgroundPrimary))
                            .clipShape(Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                    if occurrences.count > 3 {
                        Text("+\(occurrences.count - 3)")
                            .font(.system(size: AppIconSize.sm, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: AppIconSize.md, height: AppIconSize.md)
                            .background(Circle().fill(AppColors.surface))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: occurrences.count)
            } else {
                Spacer().frame(height: AppIconSize.md)
            }
        }
        .frame(height: 60)
    }

    private func logoView(for sub: RecurringSeries, size: CGFloat) -> some View {
        // REFACTORED 2026-02-02: Use IconView to eliminate duplication
        IconView(
            source: sub.iconSource,
            size: size
        )
    }

    // MARK: - Helpers

    private func calculateCalendarHeight() -> CGFloat {
        // Calculate number of weeks needed for the current month
        let currentMonth = allMonths[currentMonthIndex]
        let days = calendarDays(for: currentMonth)
        let weeksCount = ceil(Double(days.count) / 7.0)

        // Cell height (60) * weeks + spacing between rows
        let cellHeight: CGFloat = 60
        let rowSpacing: CGFloat = AppSpacing.xs * (weeksCount - 1)
        let gridHeight = (cellHeight * weeksCount) + rowSpacing

        // Top padding only (weekday headers are now outside TabView)
        let topPadding: CGFloat = AppSpacing.md

        return gridHeight + topPadding
    }

    private func calculateAllMonthTotals() async {
        var totals: [Int: Decimal] = [:]

        for (index, monthDate) in allMonths.enumerated() {
            let monthStart = calendar.startOfDay(for: monthDate)
            guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
                continue
            }

            let monthInterval = DateInterval(start: monthStart, end: monthEnd)
            var monthTotal: Decimal = 0

            for subscription in subscriptions {
                let occurrences = subscription.occurrences(in: monthInterval)
                if !occurrences.isEmpty {
                    // Convert to base currency
                    let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
                    let convertedAmount = await CurrencyConverter.convert(
                        amount: amount,
                        from: subscription.currency,
                        to: baseCurrency
                    ) ?? amount

                    monthTotal += Decimal(convertedAmount) * Decimal(occurrences.count)
                }
            }

            totals[index] = monthTotal
        }

        monthlyTotals = totals
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstDay = calendar.firstWeekday // 1 = Sunday, 2 = Monday

        var rotated = Array(symbols[firstDay-1..<symbols.count])
        rotated.append(contentsOf: symbols[0..<firstDay-1])
        return rotated
    }

    private func calendarDays(for monthStart: Date) -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart),
              let firstDayOfMonth = calendar.date(
                  from: calendar.dateComponents([.year, .month], from: monthStart)
              ) else {
            return []
        }

        let weekdayOfFirst = calendar.component(.weekday, from: firstDayOfMonth)
        let firstDayIndex = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [CalendarDay] = (0..<firstDayIndex).map { i in
            CalendarDay(id: "empty-\(i)", date: nil)
        }

        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                guard let year = comps.year, let month = comps.month, let day = comps.day else { continue }
                let id = "\(year)-\(month)-\(day)"
                days.append(CalendarDay(id: id, date: date))
            }
        }
        return days
    }

    private func formatMonthYear(_ date: Date) -> String {
        Self.monthYearFormatter.string(from: date).capitalized
    }

    private func subscriptionsOnDate(_ date: Date) -> [RecurringSeries] {
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: date) else { return [] }
        let dayInterval = DateInterval(start: date, end: endDate.addingTimeInterval(-1))
        return subscriptions.filter { sub in
            !sub.occurrences(in: dayInterval).isEmpty
        }
    }
}

#Preview("With Subscriptions") {
    let calendar = Calendar.current
    let today = Date()
    let formatter = ISO8601DateFormatter()

    // Create mock subscriptions with various dates throughout the month
    let mockSubscriptions = [
        RecurringSeries(
            amount: 9.99,
            currency: "USD",
            category: "Развлечения",
            description: "Netflix",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("netflix")
        ),
        RecurringSeries(
            amount: 14.99,
            currency: "USD",
            category: "Развлечения",
            description: "Spotify",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 12, to: calendar.startOfDay(for: today))!),
            iconSource: .brandService("spotify")
        ),
        RecurringSeries(
            amount: 299,
            currency: "RUB",
            category: "Коммуналка",
            description: "Интернет",
            frequency: .monthly,
            startDate: formatter.string(from: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!)
        ),
        RecurringSeries(
            amount: 4.99,
            currency: "USD",
            category: "Облако",
            description: "iCloud Storage",
            frequency: .monthly,
            startDate: formatter.string(from: today),
            iconSource: .brandService("icloud")
        )
    ]

    SubscriptionCalendarView(subscriptions: mockSubscriptions, baseCurrency: "USD")
        .padding()
}

#Preview("Empty Calendar") {
    SubscriptionCalendarView(subscriptions: [], baseCurrency: "USD")
        .padding()
}
