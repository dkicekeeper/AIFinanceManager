//
//  SubcategoryPickerView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubcategoryPickerView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let categoryId: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var showingCreateSubcategory = false
    @State private var newSubcategoryName = ""
    
    private var availableSubcategories: [Subcategory] {
        let linkedSubcategoryIds = viewModel.categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }
        
        let allSubcategories = searchText.isEmpty
            ? viewModel.subcategories
            : viewModel.searchSubcategories(query: searchText)
        
        return allSubcategories.filter { !linkedSubcategoryIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Поиск
                TextField("Поиск подкатегорий", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                // Список подкатегорий
                List {
                    ForEach(availableSubcategories) { subcategory in
                        Button(action: {
                            onSelect(subcategory.id)
                        }) {
                            Text(subcategory.name)
                        }
                    }
                }
                
                // Кнопка создания новой подкатегории
                Button(action: {
                    showingCreateSubcategory = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Создать новую подкатегорию")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Выберите подкатегорию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCreateSubcategory) {
                CreateSubcategoryView(viewModel: viewModel) { subcategory in
                    onSelect(subcategory.id)
                    showingCreateSubcategory = false
                }
            }
        }
    }
}

struct CreateSubcategoryView: View {
    @ObservedObject var viewModel: TransactionsViewModel
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
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let subcategory = viewModel.addSubcategory(name: name)
                        onSave(subcategory)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

#Preview {
    SubcategoryPickerView(viewModel: TransactionsViewModel(), categoryId: "", onSelect: { _ in })
}
