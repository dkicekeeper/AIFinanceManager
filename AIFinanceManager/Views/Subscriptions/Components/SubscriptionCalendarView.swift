//
//  SubscriptionCalendarView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

enum CalendarViewType: String, CaseIterable, Identifiable {
    case month = "month"
    case halfYear = "halfYear"
    case year = "year"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .month: return String(localized: "calendar.month")
        case .halfYear: return String(localized: "calendar.halfYear")
        case .year: return String(localized: "calendar.year")
        }
    }
    
    var daysCount: Int {
        switch self {
        case .month: return 30
        case .halfYear: return 182
        case .year: return 365
        }
    }
}

struct SubscriptionCalendarView: View {
    let subscriptions: [RecurringSeries]
    @State private var viewType: CalendarViewType = .month
    private let calendar = Calendar.current
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            header
            
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    ForEach(monthsInPeriod, id: \.self) { monthStart in
                        monthGrid(for: monthStart)
                    }
                }
                .padding(.vertical, AppSpacing.sm)
            }
            .frame(maxHeight: viewType == .month ? 350 : 500)
        }
        .glassCardStyle()
    }
    
    private var header: some View {
        HStack {
            Text(String(localized: "calendar.upcomingPayments"))
                .font(AppTypography.h4)

            Spacer()

            Picker("View Type", selection: $viewType) {
                ForEach(CalendarViewType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: AppSize.calendarPickerWidth)
        }
    }
    
    private var monthsInPeriod: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return [today]
        }
        
        let count: Int
        switch viewType {
        case .month: count = 1
        case .halfYear: count = 6
        case .year: count = 12
        }
        
        return (0..<count).compactMap { i in
            calendar.date(byAdding: .month, value: i, to: startOfMonth)
        }
    }
    
    private func monthGrid(for monthStart: Date) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(formatMonthName(monthStart))
                .font(AppTypography.bodyLarge)
                .padding(.leading, AppSpacing.xs)
            
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(height: AppSize.skeletonHeight)
                }
            }
            
            // Days grid
            LazyVGrid(columns: columns, spacing: 0) {
                let days = daysInMonth(for: monthStart)
                ForEach(0..<days.count, id: \.self) { index in
                    if let date = days[index] {
                        dateCell(for: date)
                    } else {
                        Color.clear
                            .frame(height: 45)
                    }
                }
            }
        }
    }
    
    private func dateCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let occurrences = subscriptionsOnDate(date)

        return VStack(spacing: AppSpacing.xxs) {
            Text("\(calendar.component(.day, from: date))")
                .font(isToday ? AppTypography.captionEmphasis : AppTypography.caption)
                .foregroundColor(isToday ? AppColors.accent : AppColors.textPrimary)
                .frame(width: AppIconSize.lg, height: AppIconSize.lg)
                .background(isToday ? AppColors.accent.opacity(0.1) : Color.clear)
                .clipShape(Circle())

            // Logos
            if !occurrences.isEmpty {
                HStack(spacing: -AppSpacing.xs) {
                    ForEach(occurrences.prefix(3), id: \.id) { sub in
                        logoView(for: sub, size: AppIconSize.indicator)
                            .background(Circle().fill(AppColors.backgroundPrimary))
                            .clipShape(Circle())
                    }
                    if occurrences.count > 3 {
                        Text("+\(occurrences.count - 3)")
                            .font(.system(size: AppIconSize.xs, weight: .bold))
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: AppIconSize.indicator, height: AppIconSize.indicator)
                            .background(Circle().fill(AppColors.surface))
                    }
                }
            } else {
                Spacer().frame(height: AppIconSize.indicator)
            }
        }
        .frame(height: AppSize.buttonSmall + 5)
    }
    
    private func logoView(for sub: RecurringSeries, size: CGFloat) -> some View {
        // REFACTORED 2026-02-02: Use BrandLogoDisplayView to eliminate duplication
        BrandLogoDisplayView(
            brandLogo: sub.brandLogo,
            brandId: sub.brandId,
            brandName: sub.description,
            size: size
        )
    }
    
    // MARK: - Helpers
    
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstDay = calendar.firstWeekday // 1 = Sunday, 2 = Monday
        
        var rotated = Array(symbols[firstDay-1..<symbols.count])
        rotated.append(contentsOf: symbols[0..<firstDay-1])
        return rotated
    }
    
    private func daysInMonth(for monthStart: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart)) else {
            return []
        }
        
        let weekdayOfFirst = calendar.component(.weekday, from: firstDayOfMonth)
        let firstDayIndex = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        
        var days: [Date?] = Array(repeating: nil, count: firstDayIndex)
        
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func formatMonthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date).capitalized
    }
    
    private func subscriptionsOnDate(_ date: Date) -> [RecurringSeries] {
        let dayInterval = DateInterval(start: date, end: calendar.date(byAdding: .day, value: 1, to: date)!.addingTimeInterval(-1))
        return subscriptions.filter { sub in
            !sub.occurrences(in: dayInterval).isEmpty
        }
    }
}
