//
//  CSVImportResultView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CSVImportResultView: View {
    let result: ImportResult
    let onDismiss: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Иконка результата
                Image(systemName: result.importedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(result.importedCount > 0 ? .green : .orange)
                
                // Статистика
                VStack(spacing: 16) {
                    StatRow(label: "Импортировано операций", value: "\(result.importedCount)", color: .green)
                    
                    if result.duplicatesSkipped > 0 {
                        StatRow(
                            label: "Дубликаты пропущены",
                            value: "\(result.duplicatesSkipped)",
                            color: .purple,
                            icon: "arrow.triangle.2.circlepath"
                        )
                    }
                    
                    if result.skippedCount - result.duplicatesSkipped > 0 {
                        StatRow(
                            label: "Пропущено (ошибки)",
                            value: "\(result.skippedCount - result.duplicatesSkipped)",
                            color: .orange
                        )
                    }
                    
                    if result.createdAccounts > 0 {
                        StatRow(label: "Создано счетов", value: "\(result.createdAccounts)", color: .blue)
                    }
                    
                    if result.createdCategories > 0 {
                        StatRow(label: "Создано категорий", value: "\(result.createdCategories)", color: .blue)
                    }
                    
                    if result.createdSubcategories > 0 {
                        StatRow(label: "Создано подкатегорий", value: "\(result.createdSubcategories)", color: .blue)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Ошибки
                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ошибки:")
                            .font(.headline)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(result.errors.prefix(10), id: \.self) { error in
                                    Text("• \(error)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                if result.errors.count > 10 {
                                    Text("... и еще \(result.errors.count - 10) ошибок")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                Spacer()
                
                Button(action: {
                    // Закрываем все модалки
                    onDismiss()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Готово")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
            .padding()
            .navigationTitle("Результат импорта")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    let icon: String?
    
    init(label: String, value: String, color: Color, icon: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
        self.icon = icon
    }
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

#Preview {
    let result = ImportResult(
        importedCount: 10,
        skippedCount: 2,
        duplicatesSkipped: 5,
        createdAccounts: 1,
        createdCategories: 2,
        createdSubcategories: 0,
        errors: []
    )
    NavigationView {
        CSVImportResultView(result: result, onDismiss: {})
    }
}
