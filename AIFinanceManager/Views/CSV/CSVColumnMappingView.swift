//
//  CSVColumnMappingView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import Combine

struct CSVColumnMappingView: View {
    let csvFile: CSVFile
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel?
    let onComplete: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: AppCoordinator
    
    init(csvFile: CSVFile, transactionsViewModel: TransactionsViewModel, categoriesViewModel: CategoriesViewModel? = nil, onComplete: (() -> Void)? = nil) {
        self.csvFile = csvFile
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.onComplete = onComplete
    }
    
    // Получаем основной CategoriesViewModel из coordinator, если не передан
    private var mainCategoriesViewModel: CategoriesViewModel {
        if let passedViewModel = categoriesViewModel {
            return passedViewModel
        }
        // Если не передан, используем из coordinator (должен быть доступен через @EnvironmentObject)
        return coordinator.categoriesViewModel
    }
    
    @State private var mapping = CSVColumnMapping()
    @State private var showingEntityMapping = false
    @State private var showingImportResult = false
    @State private var importResult: ImportResult?
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    
    private var requiredFieldsSection: some View {
        Section(header: Text("Обязательные поля")) {
            datePicker
            if mapping.dateColumn != nil {
                dateFormatPicker
            }
            typePicker
            amountPicker
        }
    }
    
    private var optionalFieldsSection: some View {
        Section(header: Text("Опциональные поля")) {
            currencyPicker
            accountPicker
            targetAccountPicker
            targetCurrencyPicker
            targetAmountPicker
            categoryPicker
            subcategoriesPicker
            if mapping.subcategoriesColumn != nil {
                subcategoriesSeparatorPicker
            }
            notePicker
        }
    }
    
    private var datePicker: some View {
        Picker("Дата", selection: Binding(
            get: { mapping.dateColumn ?? "" },
            set: { mapping.dateColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var dateFormatPicker: some View {
        Picker("Формат даты", selection: $mapping.dateFormat) {
            ForEach(DateFormatType.allCases, id: \.self) { format in
                Text(format.rawValue).tag(format)
            }
        }
    }
    
    private var typePicker: some View {
        Picker("Тип операции", selection: Binding(
            get: { mapping.typeColumn ?? "" },
            set: { mapping.typeColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var amountPicker: some View {
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
    
    private var currencyPicker: some View {
        Picker("Валюта", selection: Binding(
            get: { mapping.currencyColumn ?? "" },
            set: { mapping.currencyColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var accountPicker: some View {
        Picker("Счёт", selection: Binding(
            get: { mapping.accountColumn ?? "" },
            set: { mapping.accountColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var targetAccountPicker: some View {
        Picker("Счёт получателя", selection: Binding(
            get: { mapping.targetAccountColumn ?? "" },
            set: { mapping.targetAccountColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var targetCurrencyPicker: some View {
        Picker("Валюта счета получателя", selection: Binding(
            get: { mapping.targetCurrencyColumn ?? "" },
            set: { mapping.targetCurrencyColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var targetAmountPicker: some View {
        Picker("Сумма счета получателя", selection: Binding(
            get: { mapping.targetAmountColumn ?? "" },
            set: { mapping.targetAmountColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var categoryPicker: some View {
        Picker("Категория", selection: Binding(
            get: { mapping.categoryColumn ?? "" },
            set: { mapping.categoryColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var subcategoriesPicker: some View {
        Picker("Подкатегории", selection: Binding(
            get: { mapping.subcategoriesColumn ?? "" },
            set: { mapping.subcategoriesColumn = $0.isEmpty ? nil : $0 }
        )) {
            Text("— не использовать —").tag("")
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }
    
    private var subcategoriesSeparatorPicker: some View {
        Picker("Разделитель подкатегорий", selection: $mapping.subcategoriesSeparator) {
            Text("; (точка с запятой)").tag(";")
            Text(", (запятая)").tag(",")
            Text("| (вертикальная черта)").tag("|")
        }
    }
    
    private var notePicker: some View {
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
    
    var body: some View {
        NavigationView {
            Form {
                requiredFieldsSection
                optionalFieldsSection
            }
            .navigationTitle("Мэтчинг колонок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showingEntityMapping) {
                entityMappingSheet
            }
            .sheet(isPresented: Binding(
                get: { showingImportResult && importResult != nil },
                set: { showingImportResult = $0 }
            )) {
                importResultSheet
            }
            .overlay {
                importOverlay
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
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
    }
    
    private var entityMappingSheet: some View {
        CSVEntityMappingView(
            csvFile: csvFile,
            mapping: mapping,
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: AccountsViewModel(repository: transactionsViewModel.repository),
            categoriesViewModel: mainCategoriesViewModel,
            onComplete: { entityMapping in
                Task {
                    await performImport(entityMapping: entityMapping)
                }
            }
        )
    }
    
    @ViewBuilder
    private var importResultSheet: some View {
        if let result = importResult {
            CSVImportResultView(result: result) {
                // Закрываем все модалки после успешного импорта
                dismiss()
                onComplete?()
            }
        }
    }
    
    @ViewBuilder
    private var importOverlay: some View {
        if isImporting {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                ProgressView(value: importProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Импорт данных... \(Int(importProgress * 100))%")
                    .font(AppTypography.body)
            }
            .padding(AppSpacing.lg)
            .background(Color(.systemBackground))
            .cornerRadius(AppRadius.md)
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
            importProgress = 0.0
        }
        
        // Используем основной CategoriesViewModel (из coordinator или переданный)
        let importCategoriesViewModel = await MainActor.run {
            mainCategoriesViewModel
        }
        let accountsViewModel = AccountsViewModel(repository: transactionsViewModel.repository)
        
        let result = await CSVImportService.importTransactions(
            csvFile: csvFile,
            columnMapping: mapping,
            entityMapping: entityMapping,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: importCategoriesViewModel,
            accountsViewModel: accountsViewModel,
            progressCallback: { progress in
                Task { @MainActor in
                    importProgress = progress
                }
            }
        )
        
        await MainActor.run {
            isImporting = false
            importProgress = 1.0
            importResult = result

            // НЕ перезагружаем данные в CategoriesViewModel - они уже актуальны
            // после импорта и синхронно сохранены в UserDefaults
            // Перезагрузка только затрет изменения в памяти!
            // mainCategoriesViewModel.reloadFromStorage()

            // Перезагружаем данные в AccountsViewModel из coordinator
            // потому что импорт использует ДРУГОЙ экземпляр AccountsViewModel
            coordinator.accountsViewModel.reloadFromStorage()

            // Принудительно обновляем UI во всех ViewModels
            transactionsViewModel.objectWillChange.send()
            coordinator.accountsViewModel.objectWillChange.send()
            mainCategoriesViewModel.objectWillChange.send()

            showingImportResult = true
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let sampleCSV = CSVFile(
        headers: ["Date", "Amount", "Description", "Category"],
        rows: [
            ["2024-01-01", "1000", "Test", "Food"]
        ],
        preview: [
            ["2024-01-01", "1000", "Test", "Food"]
        ]
    )
    NavigationView {
        CSVColumnMappingView(csvFile: sampleCSV, transactionsViewModel: coordinator.transactionsViewModel)
    }
}
