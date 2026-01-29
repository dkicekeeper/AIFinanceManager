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
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let onComplete: (EntityMapping) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var entityMapping = EntityMapping()
    @State private var uniqueAccounts: [String] = []
    @State private var uniqueCategories: [String] = []
    @State private var uniqueIncomeCategories: [String] = []
    @State private var accountMappings: [String: String] = [:] // CSV значение -> Account ID
    @State private var categoryMappings: [String: String] = [:] // CSV значение -> Category name
    @State private var showingAccountCreation = false
    @State private var showingCategoryCreation = false
    @State private var selectedAccountValue: String?
    @State private var selectedCategoryValue: String?
    
    var body: some View {
        NavigationView {
            Form {
                if !uniqueAccounts.isEmpty {
                    Section(header: Text("Сопоставление счетов")) {
                        ForEach(uniqueAccounts, id: \.self) { accountValue in
                            NavigationLink(destination: AccountMappingDetailView(
                                csvValue: accountValue,
                                accounts: accountsViewModel.accounts,
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
                                       let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) {
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
                
                if mapping.categoryColumn != nil, !uniqueCategories.isEmpty {
                    Section(header: Text("Сопоставление категорий")) {
                        ForEach(uniqueCategories, id: \.self) { categoryValue in
                            NavigationLink(destination: CategoryMappingDetailView(
                                csvValue: categoryValue,
                                categories: categoriesViewModel.customCategories.filter { $0.type == .expense },
                                categoryType: .expense,
                                selectedCategoryName: Binding(
                                    get: { categoryMappings[categoryValue] },
                                    set: { categoryMappings[categoryValue] = $0 }
                                ),
                                onCreateNew: {
                                    createCategory(name: categoryValue, type: .expense)
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
                
                if !uniqueIncomeCategories.isEmpty {
                    Section(header: Text("Сопоставление категорий доходов")) {
                        ForEach(uniqueIncomeCategories, id: \.self) { categoryValue in
                            NavigationLink(destination: CategoryMappingDetailView(
                                csvValue: categoryValue,
                                categories: categoriesViewModel.customCategories.filter { $0.type == .income },
                                categoryType: .income,
                                selectedCategoryName: Binding(
                                    get: { categoryMappings[categoryValue] },
                                    set: { categoryMappings[categoryValue] = $0 }
                                ),
                                onCreateNew: {
                                    createCategory(name: categoryValue, type: .income)
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
    
    private func parseType(_ typeString: String) -> TransactionType? {
        let n = typeString.lowercased().trimmingCharacters(in: .whitespaces)
        if let t = mapping.typeMappings[n] { return t }
        for (key, type) in mapping.typeMappings {
            if n.contains(key) || key.contains(n) { return type }
        }
        return nil
    }
    
    private func extractUniqueValues() {
        let headers = csvFile.headers
        let typeIdx = mapping.typeColumn.flatMap { headers.firstIndex(of: $0) }
        let accountIdx = mapping.accountColumn.flatMap { headers.firstIndex(of: $0) }
        let targetIdx = mapping.targetAccountColumn.flatMap { headers.firstIndex(of: $0) }
        let categoryIdx = mapping.categoryColumn.flatMap { headers.firstIndex(of: $0) }
        
        let reserved = ["другое", "other"]
        
        var accountSet: Set<String> = []
        var expenseCategorySet: Set<String> = []
        var incomeCategorySet: Set<String> = []
        
        for row in csvFile.rows {
            let typeStr = typeIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let type = parseType(typeStr)
            let accountVal = accountIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let targetVal = targetIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let categoryVal = categoryIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            
            switch type {
            case .income:
                if !targetVal.isEmpty { accountSet.insert(targetVal) }
                if !accountVal.isEmpty { incomeCategorySet.insert(accountVal) }
            case .expense, .internalTransfer, .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                if !accountVal.isEmpty, !reserved.contains(accountVal.lowercased()) { accountSet.insert(accountVal) }
                if type == .expense, !categoryVal.isEmpty { expenseCategorySet.insert(categoryVal) }
            case .none:
                if !accountVal.isEmpty, !reserved.contains(accountVal.lowercased()) { accountSet.insert(accountVal) }
                if !categoryVal.isEmpty { expenseCategorySet.insert(categoryVal) }
            }
        }
        
        uniqueAccounts = Array(accountSet).sorted()
        uniqueCategories = Array(expenseCategorySet).sorted()
        uniqueIncomeCategories = Array(incomeCategorySet).sorted()
    }
    
    private func createAccount(name: String) {
        accountsViewModel.addAccount(name: name, balance: 0, currency: "KZT", bankLogo: .none)
        if let account = accountsViewModel.accounts.first(where: { $0.name == name }) {
            accountMappings[name] = account.id
        }
    }
    
    private func createCategory(name: String, type: TransactionType = .expense) {
        let iconName = CategoryIcon.iconName(for: name, type: type, customCategories: categoriesViewModel.customCategories)
        let colorHex = CategoryColors.hexColor(for: name, customCategories: categoriesViewModel.customCategories)
        let hexString = colorToHex(colorHex)
        
        let newCategory = CustomCategory(
            name: name,
            iconName: iconName,
            colorHex: hexString,
            type: type
        )
        categoriesViewModel.addCategory(newCategory)
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
    var categoryType: TransactionType = .expense
    @Binding var selectedCategoryName: String?
    let onCreateNew: () -> Void
    
    private var categoryLabel: String {
        categoryType == .income ? "категорию дохода" : "категорию"
    }
    
    var body: some View {
        Form {
            Section(header: Text("Выберите \(categoryLabel) для \"\(csvValue)\"")) {
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
                        Text("Создать новую \(categoryLabel) \"\(csvValue)\"")
                    }
                }
            }
        }
        .navigationTitle(categoryType == .income ? "Сопоставление категории дохода" : "Сопоставление категории")
    }
}

