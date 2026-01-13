//
//  CSVEntityMappingView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI
import UIKit

struct CSVEntityMappingView: View {
    let csvFile: CSVFile
    let mapping: CSVColumnMapping
    let viewModel: TransactionsViewModel
    let onComplete: (EntityMapping) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var entityMapping = EntityMapping()
    @State private var uniqueAccounts: [String] = []
    @State private var uniqueCategories: [String] = []
    @State private var accountMappings: [String: String] = [:] // CSV значение -> Account ID
    @State private var categoryMappings: [String: String] = [:] // CSV значение -> Category name
    @State private var showingAccountCreation = false
    @State private var showingCategoryCreation = false
    @State private var selectedAccountValue: String?
    @State private var selectedCategoryValue: String?
    
    var body: some View {
        NavigationView {
            Form {
                if mapping.accountColumn != nil {
                    Section(header: Text("Сопоставление счетов")) {
                        ForEach(uniqueAccounts, id: \.self) { accountValue in
                            NavigationLink(destination: AccountMappingDetailView(
                                csvValue: accountValue,
                                accounts: viewModel.accounts,
                                selectedAccountId: Binding(
                                    get: { accountMappings[accountValue] },
                                    set: { accountMappings[accountValue] = $0 }
                                ),
                                onCreateNew: {
                                    createAccount(name: accountValue)
                                }
                            )) {
                                HStack {
                                    Text(accountValue)
                                    Spacer()
                                    if let accountId = accountMappings[accountValue],
                                       let account = viewModel.accounts.first(where: { $0.id == accountId }) {
                                        Text(account.name)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Не выбрано")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if mapping.categoryColumn != nil {
                    Section(header: Text("Сопоставление категорий")) {
                        ForEach(uniqueCategories, id: \.self) { categoryValue in
                            NavigationLink(destination: CategoryMappingDetailView(
                                csvValue: categoryValue,
                                categories: viewModel.customCategories,
                                selectedCategoryName: Binding(
                                    get: { categoryMappings[categoryValue] },
                                    set: { categoryMappings[categoryValue] = $0 }
                                ),
                                onCreateNew: {
                                    createCategory(name: categoryValue)
                                }
                            )) {
                                HStack {
                                    Text(categoryValue)
                                    Spacer()
                                    if let categoryName = categoryMappings[categoryValue] {
                                        Text(categoryName)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Не выбрано")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Сопоставление сущностей")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        entityMapping.accountMappings = accountMappings
                        entityMapping.categoryMappings = categoryMappings
                        // Закрываем модалку сопоставления сущностей перед началом импорта
                        dismiss()
                        // Запускаем импорт после небольшой задержки, чтобы модалка успела закрыться
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onComplete(entityMapping)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .onAppear {
                extractUniqueValues()
            }
        }
    }
    
    private func extractUniqueValues() {
        // Извлекаем уникальные значения счетов
        if let accountColumn = mapping.accountColumn,
           let columnIndex = csvFile.headers.firstIndex(of: accountColumn) {
            uniqueAccounts = Array(Set(csvFile.rows.compactMap { row in
                row[safe: columnIndex]?.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty })).sorted()
        }
        
        // Извлекаем уникальные значения категорий
        if let categoryColumn = mapping.categoryColumn,
           let columnIndex = csvFile.headers.firstIndex(of: categoryColumn) {
            uniqueCategories = Array(Set(csvFile.rows.compactMap { row in
                row[safe: columnIndex]?.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty })).sorted()
        }
    }
    
    private func createAccount(name: String) {
        viewModel.addAccount(name: name, balance: 0, currency: "KZT", bankLogo: .none)
        if let account = viewModel.accounts.first(where: { $0.name == name }) {
            accountMappings[name] = account.id
        }
    }
    
    private func createCategory(name: String) {
        // Определяем тип категории по умолчанию (expense)
        // Используем автоматический подбор иконки и цвета
        let iconName = CategoryIcon.iconName(for: name, type: .expense, customCategories: viewModel.customCategories)
        let colorHex = CategoryColors.hexColor(for: name, customCategories: viewModel.customCategories)
        // Конвертируем Color в hex строку
        let hexString = colorToHex(colorHex)
        
        let newCategory = CustomCategory(
            name: name,
            iconName: iconName,
            colorHex: hexString,
            type: .expense
        )
        viewModel.addCategory(newCategory)
        categoryMappings[name] = name
    }
    
    // Конвертирует Color в hex строку
    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct AccountMappingDetailView: View {
    let csvValue: String
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onCreateNew: () -> Void
    
    var body: some View {
        Form {
            Section(header: Text("Выберите счет для \"\(csvValue)\"")) {
                ForEach(accounts) { account in
                    Button(action: {
                        selectedAccountId = account.id
                    }) {
                        HStack {
                            account.bankLogo.image(size: 24)
                            Text(account.name)
                            Spacer()
                            if selectedAccountId == account.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            Section {
                Button(action: onCreateNew) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Создать новый счет \"\(csvValue)\"")
                    }
                }
            }
        }
        .navigationTitle("Сопоставление счета")
    }
}

struct CategoryMappingDetailView: View {
    let csvValue: String
    let categories: [CustomCategory]
    @Binding var selectedCategoryName: String?
    let onCreateNew: () -> Void
    
    var body: some View {
        Form {
            Section(header: Text("Выберите категорию для \"\(csvValue)\"")) {
                ForEach(categories, id: \.name) { category in
                    Button(action: {
                        selectedCategoryName = category.name
                    }) {
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundColor(category.color)
                            Text(category.name)
                            Spacer()
                            if selectedCategoryName == category.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            Section {
                Button(action: onCreateNew) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Создать новую категорию \"\(csvValue)\"")
                    }
                }
            }
        }
        .navigationTitle("Сопоставление категории")
    }
}

