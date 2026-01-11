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
            .dateButton()
            .disabled(isDisabled)

            // Сегодня - в центре
            Button(action: {
                let today = Date()
                selectedDate = today
                onSave(today)
            }) {
                Text("Сегодня")
            }
            .dateButton()
            .disabled(isDisabled)

            // Календарь - справа
            Button(action: {
                showingDatePicker = true
            }) {
                Text("Календарь")
            }
            .dateButton()
            .disabled(isDisabled)
        }
        .cornerRadius(AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .opacity(isDisabled ? 0.6 : 1.0)
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
