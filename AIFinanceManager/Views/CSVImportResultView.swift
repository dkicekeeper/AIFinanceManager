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
            VStack(spacing: AppSpacing.xxl) {
                // Иконка результата
                Image(systemName: result.importedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: AppIconSize.coin))
                    .foregroundColor(result.importedCount > 0 ? AppColors.success : AppColors.warning)

                // Статистика
                VStack(spacing: AppSpacing.lg) {
                    StatRow(label: "Импортировано операций", value: "\(result.importedCount)", color: AppColors.success)

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
                            color: AppColors.warning
                        )
                    }

                    if result.createdAccounts > 0 {
                        StatRow(label: "Создано счетов", value: "\(result.createdAccounts)", color: AppColors.accent)
                    }

                    if result.createdCategories > 0 {
                        StatRow(label: "Создано категорий", value: "\(result.createdCategories)", color: AppColors.accent)
                    }

                    if result.createdSubcategories > 0 {
                        StatRow(label: "Создано подкатегорий", value: "\(result.createdSubcategories)", color: AppColors.accent)
                    }
                }
                .cardContentPadding()
                .background(AppColors.surface)
                .cornerRadius(AppRadius.card)

                // Ошибки
                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Ошибки:")
                            .font(AppTypography.h4)

                        ScrollView {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                ForEach(result.errors.prefix(10), id: \.self) { error in
                                    Text("• \(error)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.destructive)
                                }

                                if result.errors.count > 10 {
                                    Text("... и еще \(result.errors.count - 10) ошибок")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                        .frame(maxHeight: AppSize.resultListHeight)
                    }
                    .cardContentPadding()
                    .background(AppColors.surface)
                    .cornerRadius(AppRadius.card)
                }

                Spacer()

                Button(action: {
                    // Закрываем все модалки
                    onDismiss()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Готово")
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(AppRadius.button)
                }
                .cardContentPadding()
            }
            .screenPadding()
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
