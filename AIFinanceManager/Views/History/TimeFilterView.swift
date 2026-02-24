//
//  TimeFilterView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct TimeFilterView: View {
    @Bindable var filterManager: TimeFilterManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPreset: TimeFilterPreset
    @State private var customStartDate: Date
    @State private var customEndDate: Date
    @State private var showingCustomPicker = false

    init(filterManager: TimeFilterManager) {
        self.filterManager = filterManager
        _selectedPreset = State(initialValue: filterManager.currentFilter.preset)
        _customStartDate = State(initialValue: filterManager.currentFilter.startDate)
        _customEndDate = State(initialValue: filterManager.currentFilter.endDate)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(String(localized: "timeFilter.presets", defaultValue: "Пресеты"))) {
                    ForEach(TimeFilterPreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                        Button(action: {
                            selectedPreset = preset
                            filterManager.setPreset(preset)
                            dismiss()
                        }) {
                            HStack {
                                Text(preset.localizedName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppColors.accent)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text(String(localized: "timeFilter.customPeriod", defaultValue: "Пользовательский период"))) {
                    Button(action: {
                        selectedPreset = .custom
                        showingCustomPicker = true
                    }) {
                        HStack {
                            Text(String(localized: "timeFilter.customPeriod", defaultValue: "Пользовательский период"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if selectedPreset == .custom {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }

                    if selectedPreset == .custom {
                        DatePicker(String(localized: "timeFilter.from", defaultValue: "С"), selection: $customStartDate, displayedComponents: .date)
                            .datePickerStyle(.compact)

                        DatePicker(String(localized: "timeFilter.to", defaultValue: "По"), selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)

                        Button(action: {
                            filterManager.setCustomRange(start: customStartDate, end: customEndDate)
                            dismiss()
                        }) {
                            Text(String(localized: "button.apply", defaultValue: "Применить"))
                                .frame(maxWidth: .infinity)
                                .padding(AppSpacing.md)
                                .background(customEndDate >= customStartDate ? AppColors.accent : AppColors.secondaryBackground)
                                .foregroundStyle(.white)
                                .clipShape(.rect(cornerRadius: AppRadius.button))
                        }
                        .disabled(customEndDate < customStartDate)
                    }
                }
            }
            .navigationTitle(String(localized: "timeFilter.title", defaultValue: "Фильтр по времени"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview("Default") {
    NavigationStack {
        TimeFilterView(filterManager: TimeFilterManager())
    }
}

#Preview("Custom Range") {
    let manager = TimeFilterManager()
    manager.setCustomRange(
        start: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
        end: Date()
    )
    return NavigationStack {
        TimeFilterView(filterManager: manager)
    }
}
