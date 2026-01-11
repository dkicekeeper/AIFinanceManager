//
//  CSVPreviewView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CSVPreviewView: View {
    let csvFile: CSVFile
    let viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingMapping = false
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Информация о файле
                VStack(alignment: .leading, spacing: 8) {
                    Text("Информация о файле")
                        .font(.headline)
                    
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
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Заголовки
                VStack(alignment: .leading, spacing: 8) {
                    Text("Колонки в файле")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(csvFile.headers, id: \.self) { header in
                                Text(header)
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
                
                // Превью данных
                VStack(alignment: .leading, spacing: 8) {
                    Text("Превью данных (первые \(csvFile.preview.count) строк)")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(csvFile.preview.enumerated()), id: \.offset) { index, row in
                                HStack(alignment: .top) {
                                    Text("\(index + 1).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 30, alignment: .leading)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, value in
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(csvFile.headers[safe: colIndex] ?? "?")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(value.isEmpty ? "(пусто)" : value)
                                                        .font(.caption)
                                                        .lineLimit(2)
                                                }
                                                .padding(6)
                                                .frame(width: 120, alignment: .leading)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding()
                
                Spacer()
                
                Button(action: {
                    showingMapping = true
                }) {
                    Text("Продолжить")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
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
                    viewModel: viewModel,
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
