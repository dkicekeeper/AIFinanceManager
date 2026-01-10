//
//  DateFormatters.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

/// Кешированные DateFormatter для оптимизации производительности
enum DateFormatters {
    /// Форматтер для дат в формате "yyyy-MM-dd"
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Форматтер для времени в формате "HH:mm"
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Форматтер для отображения даты в формате "d MMMM" (русская локализация)
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Форматтер для отображения даты с годом в формате "d MMMM yyyy" (русская локализация)
    static let displayDateWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
