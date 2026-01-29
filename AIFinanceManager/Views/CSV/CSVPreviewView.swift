//
//  CSVPreviewView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CSVPreviewView: View {
    let csvFile: CSVFile
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel?
    @Environment(\.dismiss) var dismiss
    @State private var showingMapping = false
    
    init(csvFile: CSVFile, transactionsViewModel: TransactionsViewModel, categoriesViewModel: CategoriesViewModel? = nil) {
        self.csvFile = csvFile
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Информация о файле
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Информация о файле")
                        .font(AppTypography.h4)

                    HStack {
                        Text("Колонок:")
                        Spacer()
                        Text("\(csvFile.headers.count)")
                    }

                    HStack {
                        Text("Строк данных:")
                        Spacer()
                        Text("\(csvFile.rowCount)")
                    }
                }
                .cardContentPadding()
                .background(AppColors.surface)
                .cornerRadius(AppRadius.card)

                // Заголовки
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Колонки в файле")
                        .font(AppTypography.h4)

                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(csvFile.headers, id: \.self) { header in
                                Text(header)
                                    .font(AppTypography.caption)
                                    .padding(AppSpacing.sm)
                                    .background(AppColors.accent.opacity(0.2))
                                    .cornerRadius(AppRadius.compact)
                            }
                        }
                    }
                }
                .cardContentPadding()

                // Превью данных
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Превью данных (первые \(csvFile.preview.count) строк)")
                        .font(AppTypography.h4)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(Array(csvFile.preview.enumerated()), id: \.offset) { index, row in
                                HStack(alignment: .top) {
                                    Text("\(index + 1).")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                        .frame(width: 30, alignment: .leading)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: AppSpacing.sm) {
                                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, value in
                                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                                    Text(csvFile.headers[safe: colIndex] ?? "?")
                                                        .font(AppTypography.caption2)
                                                        .foregroundColor(AppColors.textSecondary)
                                                    Text(value.isEmpty ? "(пусто)" : value)
                                                        .font(AppTypography.caption)
                                                        .lineLimit(2)
                                                }
                                                .padding(AppSpacing.compact)
                                                .frame(width: AppSize.subscriptionCardWidth, alignment: .leading)
                                                .background(AppColors.surface)
                                                .cornerRadius(AppRadius.xs)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: AppSize.previewScrollHeight)
                }
                .cardContentPadding()

                Spacer()

                Button(action: {
                    showingMapping = true
                }) {
                    Text("Продолжить")
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(AppRadius.button)
                }
                .cardContentPadding()
            }
            .navigationTitle("Превью CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showingMapping) {
                CSVColumnMappingView(
                    csvFile: csvFile,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    onComplete: {
                        // Закрываем все модалки после успешного импорта
                        dismiss()
                    }
                )
            }
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
