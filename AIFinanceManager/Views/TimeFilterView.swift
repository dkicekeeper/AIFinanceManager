//
//  TimeFilterView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct TimeFilterView: View {
    @ObservedObject var filterManager: TimeFilterManager
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
        NavigationView {
            List {
                Section(header: Text("Пресеты")) {
                    ForEach(TimeFilterPreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                        Button(action: {
                            selectedPreset = preset
                            if preset != .custom {
                                filterManager.setPreset(preset)
                                dismiss()
                            }
                        }) {
                            HStack {
                                Text(preset.rawValue)
                                    .foregroundColor(.black)
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Пользовательский период")) {
                    Button(action: {
                        selectedPreset = .custom
                        showingCustomPicker = true
                    }) {
                        HStack {
                            Text("Пользовательский период")
                                .foregroundColor(.black)
                            Spacer()
                            if selectedPreset == .custom {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if selectedPreset == .custom {
                        DatePicker("С", selection: $customStartDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        
                        DatePicker("По", selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                        
                        Button(action: {
                            if customEndDate >= customStartDate {
                                filterManager.setCustomRange(start: customStartDate, end: customEndDate)
                                dismiss()
                            }
                        }) {
                            Text("Применить")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(customEndDate >= customStartDate ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(customEndDate < customStartDate)
                    }
                }
            }
            .navigationTitle("Фильтр по времени")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}
