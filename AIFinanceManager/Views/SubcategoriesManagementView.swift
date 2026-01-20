//
//  SubcategoriesManagementView.swift
//  AIFinanceManager
//
//  Management view for subcategories
//

import SwiftUI

struct SubcategoriesManagementView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddSubcategory = false
    @State private var editingSubcategory: Subcategory?
    @State private var subcategoryToDelete: Subcategory?
    @State private var showingDeleteDialog = false
    @State private var searchText = ""
    
    private var filteredSubcategories: [Subcategory] {
        if searchText.isEmpty {
            return categoriesViewModel.subcategories
        }
        return categoriesViewModel.searchSubcategories(query: searchText)
    }
    
    // Проверяем, можно ли создать новую подкатегорию из текста поиска
    private var canCreateFromSearch: Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedSearch.isEmpty else { return false }
        
        // Проверяем, что такой подкатегории еще нет
        let searchLower = trimmedSearch.lowercased()
        let exists = categoriesViewModel.subcategories.contains { subcategory in
            subcategory.name.lowercased() == searchLower
        }
        
        return !exists
    }
    
    var body: some View {
        Group {
            if !searchText.isEmpty && filteredSubcategories.isEmpty {
                // Empty state когда поиск не нашел результатов
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: String(localized: "emptyState.searchNoResults"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
            } else {
                List {
                    ForEach(filteredSubcategories) { subcategory in
                        SubcategoryManagementRow(
                            subcategory: subcategory,
                            onEdit: { editingSubcategory = subcategory },
                            onDelete: {
                                subcategoryToDelete = subcategory
                                showingDeleteDialog = true
                            }
                        )
                        .padding(.vertical, AppSpacing.xs)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle(String(localized: "settings.subcategories"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "transactionForm.searchOrCreateSubcategory"))
        .safeAreaInset(edge: .bottom) {
            // Кнопка создания внизу над полем поиска
            if canCreateFromSearch {
                VStack(spacing: 0) {
                    Button(action: {
                        createSubcategoryFromSearch()
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "plus.circle.fill")
                            let subcategoryName = searchText.trimmingCharacters(in: .whitespaces)
                            Text(String(format: String(localized: "transactionForm.createSubcategory"), subcategoryName))
                                .font(AppTypography.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                    }
                    .foregroundStyle(.primary)
                }
                .glassEffect()
                .padding(.horizontal, AppSpacing.lg)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddSubcategory = true } label: { 
                    Image(systemName: "plus") 
                }
            }
        }
        .sheet(isPresented: $showingAddSubcategory) {
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: nil,
                onSave: { subcategory in
                    _ = categoriesViewModel.addSubcategory(name: subcategory.name)
                    showingAddSubcategory = false
                },
                onCancel: { showingAddSubcategory = false }
            )
        }
        .sheet(item: $editingSubcategory) { subcategory in
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: subcategory,
                onSave: { updatedSubcategory in
                    categoriesViewModel.updateSubcategory(updatedSubcategory)
                    editingSubcategory = nil
                },
                onCancel: { editingSubcategory = nil }
            )
        }
        .alert("Удалить подкатегорию?", isPresented: $showingDeleteDialog, presenting: subcategoryToDelete) { subcategory in
            Button("Отмена", role: .cancel) {
                subcategoryToDelete = nil
            }
            Button("Удалить", role: .destructive) {
                HapticManager.warning()
                categoriesViewModel.deleteSubcategory(subcategory.id)
                subcategoryToDelete = nil
            }
        } message: { subcategory in
            Text("Подкатегория \"\(subcategory.name)\" будет удалена из всех связанных категорий и транзакций.")
        }
    }
    
    private func createSubcategoryFromSearch() {
        let trimmedName = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        _ = categoriesViewModel.addSubcategory(name: trimmedName)
        // Очищаем поле поиска после создания
        searchText = ""
    }
}

struct SubcategoryManagementRow: View {
    let subcategory: Subcategory
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Название
            Text(subcategory.name)
                .font(.title3)
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct SubcategoryEditView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let subcategory: Subcategory?
    let onSave: (Subcategory) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(String(localized: "common.name"))) {
                    TextField(String(localized: "common.name"), text: $name)
                }
            }
            .navigationTitle(subcategory == nil ? String(localized: "modal.newSubcategory") : String(localized: "modal.editSubcategory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "button.cancel")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.save")) {
                        let subcategoryToSave = Subcategory(
                            id: subcategory?.id ?? UUID().uuidString,
                            name: name
                        )
                        onSave(subcategoryToSave)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = subcategory?.name ?? ""
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationView {
        SubcategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
}
