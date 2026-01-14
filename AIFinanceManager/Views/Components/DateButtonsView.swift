//
//  DateButtonsView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct DateButtonsView: View {
    @Binding var selectedDate: Date
    var isDisabled: Bool = false
    let onSave: (Date) -> Void
    @State private var showingDatePicker = false

    var body: some View {
        buttonsContent
    }
    
    // Контент кнопок для переиспользования
    @ViewBuilder
    var buttonsContent: some View {
        HStack(spacing: 0) {
            // Вчера - слева
            Button(action: {
                if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                    selectedDate = yesterday
                    onSave(yesterday)
                }
            }) {
                Text("Вчера")
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .disabled(isDisabled)

            // Сегодня - в центре
            Button(action: {
                let today = Date()
                selectedDate = today
                onSave(today)
            }) {
                Text("Сегодня")
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .disabled(isDisabled)

            // Календарь - справа
            Button(action: {
                showingDatePicker = true
            }) {
                Text("Календарь")
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .disabled(isDisabled)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                VStack {
                    DatePicker("Выберите дату", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Выберите дату")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showingDatePicker = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSave(selectedDate)
                            showingDatePicker = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - View Extension для использования в toolbar как нативный bottom bar
extension View {
    /// Добавляет DateButtonsView в toolbar как нативный bottom bar (iOS 16+)
    func dateButtonsToolbar(
        selectedDate: Binding<Date>,
        isDisabled: Bool = false,
        onSave: @escaping (Date) -> Void
    ) -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                DateButtonsToolbarContent(
                    selectedDate: selectedDate,
                    isDisabled: isDisabled,
                    onSave: onSave
                )
            }
        }
        .toolbarBackground(.visible, for: .bottomBar)
    }
}

// Вспомогательная структура для использования в toolbar
private struct DateButtonsToolbarContent: View {
    @Binding var selectedDate: Date
    var isDisabled: Bool = false
    let onSave: (Date) -> Void
    @State private var showingDatePicker = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Вчера - слева
            Button(action: {
                if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                    selectedDate = yesterday
                    onSave(yesterday)
                }
            }) {
                Text("Вчера")
            }
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)

            // Сегодня - в центре
            Button(action: {
                let today = Date()
                selectedDate = today
                onSave(today)
            }) {
                Text("Сегодня")
            }
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)

            // Календарь - справа
            Button(action: {
                showingDatePicker = true
            }) {
                Text("Календарь")
            }
            .frame(maxWidth: .infinity)
            .disabled(isDisabled)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationView {
                VStack {
                    DatePicker("Выберите дату", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Выберите дату")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showingDatePicker = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSave(selectedDate)
                            showingDatePicker = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    DateButtonsView(selectedDate: .constant(Date())) { _ in }
        .padding()
}
