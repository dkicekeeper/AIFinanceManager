//
//  SettingsView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import PhotosUI

struct SettingsView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var depositsViewModel: DepositsViewModel
    @State private var showingResetConfirmation = false
    @State private var showingRecalculateBalancesConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingCategoriesManagement = false
    @State private var showingAccountsManagement = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    
    var body: some View {
        settingsList
    }
    
    @State private var csvFile: CSVFile?
    @State private var showingPreview = false
    @State private var showingColumnMapping = false
    @State private var importError: String?
    @State private var showingError = false

    // MARK: - Main List

    private var settingsList: some View {
        List {
            generalSection
            dataManagementSection
            exportImportSection
            dangerZoneSection
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .alert("Пересчитать балансы?", isPresented: $showingRecalculateBalancesConfirmation) {
            Button("Пересчитать", role: .destructive) {
                HapticManager.success()
                transactionsViewModel.resetAndRecalculateAllBalances()
                accountsViewModel.reloadFromStorage()
                accountsViewModel.objectWillChange.send()
                transactionsViewModel.objectWillChange.send()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это пересчитает балансы всех счетов с нуля на основе транзакций. Используйте это, если балансы отображаются неправильно (например, после двойного учета транзакций).")
        }
        .alert(String(localized: "alert.deleteAllData.title"), isPresented: $showingResetConfirmation) {
            Button(String(localized: "alert.deleteAllData.confirm"), role: .destructive) {
                HapticManager.warning()
                transactionsViewModel.resetAllData()
                accountsViewModel.reloadFromStorage()
                categoriesViewModel.reloadFromStorage()
                accountsViewModel.objectWillChange.send()
                categoriesViewModel.objectWillChange.send()
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "alert.deleteAllData.message"))
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportActivityView(transactionsViewModel: transactionsViewModel)
        }
        .sheet(isPresented: $showingImportPicker) {
            DocumentPicker(contentTypes: [.commaSeparatedText, .text]) { url in
                Task {
                    await handleCSVImport(url: url)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { showingPreview && csvFile != nil },
            set: { showingPreview = $0 }
        )) {
            csvPreviewSheet
        }
        .sheet(isPresented: $showingColumnMapping) {
            columnMappingSheet
        }
        .alert(String(localized: "alert.importError.title"), isPresented: $showingError) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        } message: {
            if let error = importError {
                Text(error)
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(header: Text(String(localized: "settings.general"))) {
            baseCurrencyRow
            wallpaperRow
        }
    }

    private var dataManagementSection: some View {
        Section(header: Text(String(localized: "settings.dataManagement"))) {
            NavigationLink(destination: CategoriesManagementView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel
            )) {
                HStack {
                    Image(systemName: "tag")
                    Text(String(localized: "settings.categories"))
                }
            }

            NavigationLink(destination: SubcategoriesManagementView(
                categoriesViewModel: categoriesViewModel
            )) {
                HStack {
                    Image(systemName: "tag.fill")
                    Text(String(localized: "settings.subcategories"))
                }
            }

            NavigationLink(destination: AccountsManagementView(
                accountsViewModel: accountsViewModel,
                depositsViewModel: depositsViewModel,
                transactionsViewModel: transactionsViewModel
            )) {
                HStack {
                    Image(systemName: "creditcard")
                    Text(String(localized: "settings.accounts"))
                }
            }
        }
    }

    private var exportImportSection: some View {
        Section(header: Text(String(localized: "settings.exportImport"))) {
            Button(action: {
                showingExportSheet = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(String(localized: "settings.exportData"))
                }
            }

            Button(action: {
                showingImportPicker = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text(String(localized: "settings.importData"))
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        Section(header: Text(String(localized: "settings.dangerZone"))) {
            Button(action: {
                showingRecalculateBalancesConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Пересчитать балансы счетов")
                        .foregroundColor(.orange)
                }
            }

            Button(role: .destructive, action: {
                showingResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text(String(localized: "settings.resetData"))
                }
            }
        }
    }

    // MARK: - Rows

    private var baseCurrencyRow: some View {
        HStack {
            Image(systemName: "dollarsign.circle")
            Text(String(localized: "settings.baseCurrency"))
            Spacer()
            Picker("", selection: $transactionsViewModel.appSettings.baseCurrency) {
                ForEach(AppSettings.availableCurrencies, id: \.self) { currency in
                    Text(Formatting.currencySymbol(for: currency)).tag(currency)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: transactionsViewModel.appSettings.baseCurrency) {
                transactionsViewModel.appSettings.save()
                transactionsViewModel.invalidateCaches()
                transactionsViewModel.objectWillChange.send()
            }
        }
    }

    private var wallpaperRow: some View {
        let hasWallpaper = transactionsViewModel.appSettings.wallpaperImageName?.isEmpty == false

        return HStack {
            Image(systemName: "photo")
            Text(String(localized: "settings.wallpaper"))
            Spacer()

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack(spacing: 4) {
                    if hasWallpaper {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    Text(hasWallpaper ? String(localized: "button.change") : String(localized: "button.select"))
                        .font(.subheadline)
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { @MainActor in
                    if let newItem = newItem {
                        await loadPhoto(newItem)
                    }
                }
            }

            if hasWallpaper {
                Button(action: {
                    removeWallpaper()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var csvPreviewSheet: some View {
        if let csvFile = csvFile {
            CSVPreviewView(
                csvFile: csvFile,
                onContinue: {
                    showingPreview = false
                    showingColumnMapping = true
                },
                onCancel: {
                    showingPreview = false
                    self.csvFile = nil
                }
            )
        } else {
            VStack {
                Text("Ошибка загрузки файла")
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var columnMappingSheet: some View {
        if let csvFile = csvFile {
            CSVColumnMappingView(
                csvFile: csvFile,
                onComplete: { mapping in
                    // Start import with mapping
                    showingColumnMapping = false
                    Task {
                        await performImport(csvFile: csvFile, mapping: mapping)
                    }
                },
                onCancel: {
                    showingColumnMapping = false
                    self.csvFile = nil
                }
            )
        }
    }

    // MARK: - Helper Functions

    private func performImport(csvFile: CSVFile, mapping: CSVColumnMapping) async {
        #if DEBUG
        print("📥 [SettingsView] Starting CSV import")
        #endif

        // Use the old CSVImportService for now until we fully migrate to the new coordinator
        let result = await CSVImportService.importTransactions(
            csvFile: csvFile,
            columnMapping: mapping,
            entityMapping: EntityMapping(),
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel
        )

        #if DEBUG
        print("✅ [SettingsView] Import completed")
        print("   📊 Imported: \(result.importedCount)")
        print("   🏦 Created accounts: \(result.createdAccounts)")
        print("   ✅ NOT calling reloadFromStorage - accounts will keep their calculation mode")
        #endif

        // NOTE: We don't call reloadFromStorage() here because:
        // 1. Accounts are already registered in BalanceCoordinator during import
        // 2. Transactions are already saved
        // 3. BalanceCoordinator already recalculated balances
        // 4. reloadFromStorage() would call syncInitialBalancesToCoordinator() which marks ALL accounts as manual,
        //    overriding the shouldCalculateFromTransactions: true setting from CSV import

        await MainActor.run {
            self.csvFile = nil

            // Show result or error
            if result.errors.isEmpty {
                // Success - data already saved by CSVImportService
                HapticManager.success()
            } else {
                // Partial success or errors
                HapticManager.warning()
                let errorCount = result.errors.count
                let total = result.importedCount + result.skippedCount
                importError = "\(result.importedCount) из \(total) строк импортировано. Ошибок: \(errorCount)"
                showingError = true
            }
        }
    }

    private func handleCSVImport(url: URL) async {
        
        do {
            let file = try CSVImporter.parseCSV(from: url)
            
            await MainActor.run {
                csvFile = file
                importError = nil
                showingPreview = true
            }
        } catch {
            let errorMessage = error.localizedDescription
            
            await MainActor.run {
                importError = errorMessage
                csvFile = nil
                showingError = true
            }
        }
    }
    
    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        
        // Сохраняем изображение в Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "wallpaper_\(UUID().uuidString).jpg"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            do {
                try jpegData.write(to: fileURL)
                
                // Удаляем старое изображение, если есть
                if let oldFileName = transactionsViewModel.appSettings.wallpaperImageName,
                   oldFileName.hasPrefix("wallpaper_") {
                    let oldURL = documentsPath.appendingPathComponent(oldFileName)
                    try? FileManager.default.removeItem(at: oldURL)
                }
                
                await MainActor.run {
                    transactionsViewModel.appSettings.wallpaperImageName = fileName
                    transactionsViewModel.appSettings.save()
                    // Принудительно обновляем UI
                    transactionsViewModel.objectWillChange.send()
                }
            } catch {
            }
        }
    }
    
    private func removeWallpaper() {
        // Удаляем файл изображения
        if let fileName = transactionsViewModel.appSettings.wallpaperImageName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        transactionsViewModel.appSettings.wallpaperImageName = nil
        transactionsViewModel.appSettings.save()
        // Принудительно обновляем UI
        transactionsViewModel.objectWillChange.send()
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationView {
        SettingsView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            subscriptionsViewModel: coordinator.subscriptionsViewModel,
            depositsViewModel: coordinator.depositsViewModel
        )
    }
}
