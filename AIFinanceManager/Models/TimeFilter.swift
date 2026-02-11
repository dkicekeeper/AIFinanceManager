//
//  TimeFilter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

enum TimeFilterPreset: String, CaseIterable, Codable {
    case today
    case yesterday
    case thisWeek
    case last30Days
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear
    case allTime
    case custom

    var localizedName: String {
        switch self {
        case .today:
            return String(localized: "timeFilter.today")
        case .yesterday:
            return String(localized: "timeFilter.yesterday")
        case .thisWeek:
            return String(localized: "timeFilter.thisWeek")
        case .last30Days:
            return String(localized: "timeFilter.last30Days")
        case .thisMonth:
            return String(localized: "timeFilter.thisMonth")
        case .lastMonth:
            return String(localized: "timeFilter.lastMonth")
        case .thisYear:
            return String(localized: "timeFilter.thisYear")
        case .lastYear:
            return String(localized: "timeFilter.lastYear")
        case .allTime:
            return String(localized: "timeFilter.allTime")
        case .custom:
            return String(localized: "timeFilter.custom")
        }
    }
    
    func dateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return (start, end)
            
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.startOfDay(for: now)
            return (start, end)
            
        case .thisWeek:
            // Неделя начинается с понедельника (ISO)
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday + 5) % 7 // Понедельник = 0
            let start = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return (start, end)
            
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
            
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
            
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let components = calendar.dateComponents([.year, .month], from: lastMonth)
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
            
        case .thisYear:
            let components = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            return (start, end)
            
        case .lastYear:
            let lastYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let components = calendar.dateComponents([.year], from: lastYear)
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            return (start, end)
            
        case .allTime:
            // Очень ранняя дата и очень поздняя
            let start = Date(timeIntervalSince1970: 0)
            let end = Date(timeIntervalSinceNow: 86400 * 365 * 100) // 100 лет вперед
            return (start, end)
            
        case .custom:
            // Для custom нужно использовать конкретные даты из TimeFilter
            return (now, now)
        }
    }
}

struct TimeFilter: Codable, Equatable, Hashable {
    var preset: TimeFilterPreset
    var startDate: Date
    var endDate: Date
    
    init(preset: TimeFilterPreset, startDate: Date? = nil, endDate: Date? = nil) {
        self.preset = preset
        
        if preset == .custom, let start = startDate, let end = endDate {
            self.startDate = start
            self.endDate = end
        } else {
            let range = preset.dateRange()
            self.startDate = range.start
            self.endDate = range.end
        }
    }
    
    func dateRange() -> (start: Date, end: Date) {
        return (startDate, endDate)
    }
    
    var displayName: String {
        if preset == .custom {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            formatter.locale = Locale.current // Use system locale instead of hardcoded "ru_RU"
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
        return preset.localizedName
    }
}
