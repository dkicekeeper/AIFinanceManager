//
//  SubcategoryPickerView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubcategoryPickerView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let categoryId: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var showingCreateSubcategory = false
    @State private var newSubcategoryName = ""
    
    private var availableSubcategories: [Subcategory] {
        let linkedSubcategoryIds = categoriesViewModel.categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }
        
        let allSubcategories = searchText.isEmpty
            ? categoriesViewModel.subcategories
            : categoriesViewModel.searchSubcategories(query: searchText)
        
        return allSubcategories.filter { !linkedSubcategoryIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(availableSubcategories) { subcategory in
                    Button(action: {
                        onSelect(subcategory.id)
                    }) {
                        Text(subcategory.name)
                    }
                }
                
                // Кнопка создания новой подкатегории
                Section {
                    Button(action: {
                        showingCreateSubcategory = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Создать новую подкатегорию")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Выберите подкатегорию")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск подкатегорий")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSubcategory) {
                CreateSubcategoryView(categoriesViewModel: categoriesViewModel) { subcategory in
                    onSelect(subcategory.id)
                    showingCreateSubcategory = false
                }
            }
        }
    }
}

struct CreateSubcategoryView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let onSave: (Subcategory) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Название")) {
                    TextField("Название подкатегории", text: $name)
                }
            }
            .navigationTitle("Новая подкатегория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let subcategory = categoriesViewModel.addSubcategory(name: name)
                        onSave(subcategory)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategoryPickerView(categoriesViewModel: coordinator.categoriesViewModel, categoryId: "", onSelect: { _ in })
}
