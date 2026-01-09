//
//  SettingsView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingResetConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingCategoriesManagement = false
    @State private var showingAccountsManagement = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Управление данными")) {
                    NavigationLink(destination: CategoriesManagementView(viewModel: viewModel)) {
                        HStack {
                            Image(systemName: "tag")
                            Text("Категории")
                        }
                    }
                    
                    NavigationLink(destination: AccountsManagementView(viewModel: viewModel)) {
                        HStack {
                            Image(systemName: "creditcard")
                            Text("Счета")
                        }
                    }
                }
                
                Section(header: Text("Экспорт и импорт")) {
                    Button(action: {
                        showingExportSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Экспорт данных")
                        }
                    }
                    
                    Button(action: {
                        showingImportPicker = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Импорт данных")
                        }
                    }
                }
                
                Section(header: Text("Опасные действия")) {
                    Button(role: .destructive, action: {
                        showingResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Полный сброс данных")
                        }
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Удалить все данные?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    viewModel.resetAllData()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все операции, счета и категории будут удалены без возможности восстановления.")
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportActivityView(viewModel: viewModel)
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
                if let csvFile = csvFile {
                    CSVPreviewView(csvFile: csvFile, viewModel: viewModel)
                } else {
                    // Fallback view если csvFile стал nil
                    VStack {
                        Text("Ошибка загрузки файла")
                            .padding()
                    }
                }
            }
            .alert("Ошибка импорта", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = importError {
                    Text(error)
                }
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
}
