//
//  SubcategorySearchView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubcategorySearchView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let categoryId: String
    @Binding var selectedSubcategoryIds: Set<String>
    @Binding var searchText: String
    @Environment(\.dismiss) var dismiss
    
    @State private var showingCreateSubcategory = false
    @State private var newSubcategoryName = ""
    
    private var searchResults: [Subcategory] {
        if searchText.isEmpty {
            return viewModel.subcategories
        }
        return viewModel.searchSubcategories(query: searchText)
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(searchResults) { subcategory in
                    HStack {
                        Text(subcategory.name)
                        Spacer()
                        if selectedSubcategoryIds.contains(subcategory.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSubcategoryIds.contains(subcategory.id) {
                            selectedSubcategoryIds.remove(subcategory.id)
                        } else {
                            selectedSubcategoryIds.insert(subcategory.id)
                            // Автоматически привязываем к категории, если еще не привязана
                            if !categoryId.isEmpty {
                                viewModel.linkSubcategoryToCategory(
                                    subcategoryId: subcategory.id,
                                    categoryId: categoryId
                                )
                            }
                        }
                    }
                    .onLongPressGesture {
                        // Лонгтап для удаления привязки
                        if !categoryId.isEmpty {
                            viewModel.unlinkSubcategoryFromCategory(
                                subcategoryId: subcategory.id,
                                categoryId: categoryId
                            )
                        }
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
            .navigationTitle("Поиск подкатегорий")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск подкатегорий")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSubcategory) {
                CreateSubcategoryView(viewModel: viewModel) { subcategory in
                    selectedSubcategoryIds.insert(subcategory.id)
                    // Автоматически привязываем к категории
                    if !categoryId.isEmpty {
                        viewModel.linkSubcategoryToCategory(
                            subcategoryId: subcategory.id,
                            categoryId: categoryId
                        )
                    }
                    showingCreateSubcategory = false
                }
            }
        }
    }
}

#Preview {
    SubcategorySearchView(
        viewModel: TransactionsViewModel(),
        categoryId: "",
        selectedSubcategoryIds: .constant([]),
        searchText: .constant("")
    )
}
