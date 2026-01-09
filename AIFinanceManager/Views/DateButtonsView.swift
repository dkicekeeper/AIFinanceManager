//
//  DateButtonsView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct DateButtonsView: View {
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    @State private var showingDatePicker = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Вчера - слева
            Button(action: {
                if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                    selectedDate = yesterday
                    onDateSelected(yesterday)
                }
            }) {
                Text("Вчера")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
            }
            
            // Сегодня - в центре
            Button(action: {
                selectedDate = Date()
                onDateSelected(selectedDate)
            }) {
                Text("Сегодня")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
            }
            
            // Календарь - справа
            Button(action: {
                showingDatePicker = true
            }) {
                Text("Календарь")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
            }
        }
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
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
                        Button("Отмена") {
                            showingDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            onDateSelected(selectedDate)
                            showingDatePicker = false
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
