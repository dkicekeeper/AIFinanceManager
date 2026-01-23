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
        List {
            Section(header: Text(String(localized: "settings.general"))) {
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
                        // Инвалидируем кеш summary и categoryExpenses для пересчета в новой валюте
                        transactionsViewModel.invalidateCaches()
                        // Принудительно обновляем UI
                        transactionsViewModel.objectWillChange.send()
                    }
                }
                
                HStack {
                    Image(systemName: "photo")
                    Text(String(localized: "settings.wallpaper"))
                    Spacer()

                    let hasWallpaper = transactionsViewModel.appSettings.wallpaperImageName?.isEmpty == false

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
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .alert("Пересчитать балансы?", isPresented: $showingRecalculateBalancesConfirmation) {
            Button("Пересчитать", role: .destructive) {
                HapticManager.success()
                // Reset and recalculate all balances from scratch
                transactionsViewModel.resetAndRecalculateAllBalances()
                
                // Reload balances in AccountsViewModel
                accountsViewModel.reloadFromStorage()
                
                // Принудительно обновляем UI
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
                // Reset all data across all ViewModels
                transactionsViewModel.resetAllData()
                
                // Перезагружаем данные в других ViewModels
                accountsViewModel.reloadFromStorage()
                categoriesViewModel.reloadFromStorage()
                
                // Принудительно обновляем UI
                accountsViewModel.objectWillChange.send()
                categoriesViewModel.objectWillChange.send()
                
                // Note: Other ViewModels will reload from repository on next access
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
                // Передаем categoriesViewModel для синхронизации после импорта
                Task {
                    await handleCSVImport(url: url)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { showingPreview && csvFile != nil },
            set: { showingPreview = $0 }
        )) {
            if let csvFile = csvFile {
                CSVPreviewView(
                    csvFile: csvFile,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel
                )
            } else {
                // Fallback view если csvFile стал nil
                VStack {
                    Text("Ошибка загрузки файла")
                        .padding()
                }
            }
        }
        .alert(String(localized: "alert.importError.title"), isPresented: $showingError) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        } message: {
            if let error = importError {
                Text(error)
            }
        }
    }
    
    @State private var csvFile: CSVFile?
    @State private var showingPreview = false
    @State private var importError: String?
    @State private var showingError = false
    
    private func handleCSVImport(url: URL) async {
        print("📄 Начало импорта CSV из: \(url.path)")
        
        do {
            let file = try CSVImporter.parseCSV(from: url)
            print("✅ CSV успешно распарсен: \(file.headers.count) колонок, \(file.rowCount) строк")
            
            await MainActor.run {
                csvFile = file
                importError = nil
                showingPreview = true
            }
        } catch {
            let errorMessage = error.localizedDescription
            print("❌ Ошибка импорта CSV: \(errorMessage)")
            
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
                print("❌ Ошибка сохранения обоев: \(error)")
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
