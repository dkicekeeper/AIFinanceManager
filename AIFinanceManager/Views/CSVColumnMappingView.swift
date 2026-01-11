//
//  CSVColumnMappingView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CSVColumnMappingView: View {
    let csvFile: CSVFile
    let viewModel: TransactionsViewModel
    let onComplete: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    
    init(csvFile: CSVFile, viewModel: TransactionsViewModel, onComplete: (() -> Void)? = nil) {
        self.csvFile = csvFile
        self.viewModel = viewModel
        self.onComplete = onComplete
    }
    
    @State private var mapping = CSVColumnMapping()
    @State private var showingEntityMapping = false
    @State private var showingImportResult = false
    @State private var importResult: ImportResult?
    @State private var isImporting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Обязательные поля")) {
                    // Дата
                    Picker("Дата", selection: Binding(
                        get: { mapping.dateColumn ?? "" },
                        set: { mapping.dateColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    if mapping.dateColumn != nil {
                        Picker("Формат даты", selection: $mapping.dateFormat) {
                            ForEach(DateFormatType.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                    }
                    
                    // Тип
                    Picker("Тип операции", selection: Binding(
                        get: { mapping.typeColumn ?? "" },
                        set: { mapping.typeColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    // Сумма
                    Picker("Сумма", selection: Binding(
                        get: { mapping.amountColumn ?? "" },
                        set: { mapping.amountColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                }
                
                Section(header: Text("Опциональные поля")) {
                    // Валюта
                    Picker("Валюта", selection: Binding(
                        get: { mapping.currencyColumn ?? "" },
                        set: { mapping.currencyColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    // Счет
                    Picker("Счёт", selection: Binding(
                        get: { mapping.accountColumn ?? "" },
                        set: { mapping.accountColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    // Категория
                    Picker("Категория", selection: Binding(
                        get: { mapping.categoryColumn ?? "" },
                        set: { mapping.categoryColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    // Подкатегории
                    Picker("Подкатегории", selection: Binding(
                        get: { mapping.subcategoriesColumn ?? "" },
                        set: { mapping.subcategoriesColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                    
                    if mapping.subcategoriesColumn != nil {
                        Picker("Разделитель подкатегорий", selection: $mapping.subcategoriesSeparator) {
                            Text("; (точка с запятой)").tag(";")
                            Text(", (запятая)").tag(",")
                            Text("| (вертикальная черта)").tag("|")
                        }
                    }
                    
                    // Заметка
                    Picker("Заметка", selection: Binding(
                        get: { mapping.noteColumn ?? "" },
                        set: { mapping.noteColumn = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("— не использовать —").tag("")
                        ForEach(csvFile.headers, id: \.self) { header in
                            Text(header).tag(header)
                        }
                    }
                }
            }
            .navigationTitle("Мэтчинг колонок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if canProceed {
                            showingEntityMapping = true
                        }
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .disabled(!canProceed)
                }
            }
            .sheet(isPresented: $showingEntityMapping) {
                CSVEntityMappingView(
                    csvFile: csvFile,
                    mapping: mapping,
                    viewModel: viewModel,
                    onComplete: { entityMapping in
                        Task {
                            await performImport(entityMapping: entityMapping)
                        }
                    }
                )
            }
            .sheet(isPresented: Binding(
                get: { showingImportResult && importResult != nil },
                set: { showingImportResult = $0 }
            )) {
                if let result = importResult {
                    CSVImportResultView(result: result) {
                        // Закрываем все модалки после успешного импорта
                        dismiss()
                        onComplete?()
                    }
                }
            }
            .overlay {
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Импорт данных...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private var canProceed: Bool {
        mapping.dateColumn != nil &&
        mapping.typeColumn != nil &&
        mapping.amountColumn != nil
    }
    
    private func performImport(entityMapping: EntityMapping) async {
        await MainActor.run {
            isImporting = true
        }
        
        let result = await CSVImportService.importTransactions(
            csvFile: csvFile,
            columnMapping: mapping,
            entityMapping: entityMapping,
            viewModel: viewModel
        )
        
        await MainActor.run {
            isImporting = false
            importResult = result
            showingImportResult = true
        }
    }
}
