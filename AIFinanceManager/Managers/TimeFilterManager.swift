//
//  TimeFilterManager.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TimeFilterManager: ObservableObject {
    @Published var currentFilter: TimeFilter {
        didSet {
            saveToStorage()
        }
    }
    
    private let storageKey = "timeFilter"
    
    init() {
        // Загружаем сохраненный фильтр или используем дефолтный
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(TimeFilter.self, from: data) {
            self.currentFilter = decoded
        } else {
            // Дефолтный фильтр - этот месяц
            self.currentFilter = TimeFilter(preset: .thisMonth)
        }
    }
    
    func setFilter(_ filter: TimeFilter) {
        currentFilter = filter
    }
    
    func setPreset(_ preset: TimeFilterPreset) {
        currentFilter = TimeFilter(preset: preset)
    }
    
    func setCustomRange(start: Date, end: Date) {
        currentFilter = TimeFilter(preset: .custom, startDate: start, endDate: end)
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(currentFilter) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    // Проверяет, попадает ли дата в текущий фильтр
    func contains(date: Date) -> Bool {
        let range = currentFilter.dateRange()
        return date >= range.start && date < range.end
    }
    
    // Проверяет, попадает ли строка даты (формат yyyy-MM-dd) в текущий фильтр
    func contains(dateString: String) -> Bool {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else {
            return false
        }
        return contains(date: date)
    }
}
