//
//  SubcategorySearchView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubcategorySearchView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let categoryId: String
    @Binding var selectedSubcategoryIds: Set<String>
    @Binding var searchText: String
    @Environment(\.dismiss) var dismiss
    
    // Режим работы: множественный выбор (для транзакций) или одиночный (для привязки к категории)
    let selectionMode: SelectionMode
    let onSingleSelect: ((String) -> Void)?
    
    
    enum SelectionMode {
        case multiple // Множественный выбор для транзакций
        case single // Одиночный выбор для привязки к категории
    }
    
    init(
        categoriesViewModel: CategoriesViewModel,
        categoryId: String,
        selectedSubcategoryIds: Binding<Set<String>>,
        searchText: Binding<String>,
        selectionMode: SelectionMode = .multiple,
        onSingleSelect: ((String) -> Void)? = nil
    ) {
        self.categoriesViewModel = categoriesViewModel
        self.categoryId = categoryId
        self._selectedSubcategoryIds = selectedSubcategoryIds
        self._searchText = searchText
        self.selectionMode = selectionMode
        self.onSingleSelect = onSingleSelect
    }
    
    private var searchResults: [Subcategory] {
        let allSubcategories: [Subcategory]
        if searchText.isEmpty {
            allSubcategories = categoriesViewModel.subcategories
        } else {
            allSubcategories = categoriesViewModel.searchSubcategories(query: searchText)
        }
        
        // В режиме одиночного выбора показываем только непривязанные подкатегории
        if selectionMode == .single {
            let linkedSubcategoryIds = categoriesViewModel.categorySubcategoryLinks
                .filter { $0.categoryId == categoryId }
                .map { $0.subcategoryId }
            return allSubcategories.filter { !linkedSubcategoryIds.contains($0.id) }
        }
        
        return allSubcategories
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
        NavigationView {
            Group {
                if !searchText.isEmpty && searchResults.isEmpty {
                    // Empty state когда поиск не нашел результатов
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: String(localized: "emptyState.searchNoResults"),
                        description: String(localized: "emptyState.tryDifferentSearch")
                    )
                } else {
                    List {
                        ForEach(searchResults) { subcategory in
                            HStack {
                                Text(subcategory.name)
                                Spacer()
                                if selectionMode == .multiple && selectedSubcategoryIds.contains(subcategory.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectionMode == .single {
                                    // Одиночный выбор - вызываем callback и закрываем
                                    onSingleSelect?(subcategory.id)
                                    dismiss()
                                } else {
                                    // Множественный выбор
                                    if selectedSubcategoryIds.contains(subcategory.id) {
                                        selectedSubcategoryIds.remove(subcategory.id)
                                    } else {
                                        selectedSubcategoryIds.insert(subcategory.id)
                                        // Автоматически привязываем к категории, если еще не привязана
                                        if !categoryId.isEmpty {
                                            categoriesViewModel.linkSubcategoryToCategory(
                                                subcategoryId: subcategory.id,
                                                categoryId: categoryId
                                            )
                                        }
                                    }
                                }
                            }
                            .onLongPressGesture {
                                // Лонгтап для удаления привязки
                                if !categoryId.isEmpty {
                                    categoriesViewModel.unlinkSubcategoryFromCategory(
                                        subcategoryId: subcategory.id,
                                        categoryId: categoryId
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectionMode == .single ? "Выберите подкатегорию" : "Поиск подкатегорий")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Найти или создать подкатегорию")
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectionMode == .single {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    private func createSubcategoryFromSearch() {
        let trimmedName = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let newSubcategory = categoriesViewModel.addSubcategory(name: trimmedName)
        
        // Автоматически привязываем к категории
        if !categoryId.isEmpty {
            categoriesViewModel.linkSubcategoryToCategory(
                subcategoryId: newSubcategory.id,
                categoryId: categoryId
            )
        }
        
        if selectionMode == .single {
            // Одиночный выбор - вызываем callback и закрываем
            onSingleSelect?(newSubcategory.id)
            dismiss()
        } else {
            // Множественный выбор - добавляем в выбранные
            selectedSubcategoryIds.insert(newSubcategory.id)
            // Очищаем поле поиска после создания
            searchText = ""
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategorySearchView(
        categoriesViewModel: coordinator.categoriesViewModel,
        categoryId: "",
        selectedSubcategoryIds: .constant([]),
        searchText: .constant("")
    )
}
