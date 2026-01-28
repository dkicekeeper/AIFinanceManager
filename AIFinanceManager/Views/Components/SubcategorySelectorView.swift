//
//  SubcategorySelectorView.swift
//  AIFinanceManager
//
//  Horizontal scrollable subcategory selector with FilterChip style
//

import SwiftUI

struct SubcategorySelectorView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let categoryId: String?
    @Binding var selectedSubcategoryIds: Set<String>
    let onSearchTap: () -> Void
    
    private var availableSubcategories: [Subcategory] {
        guard let categoryId = categoryId else { return [] }
        let linkedSubcategories = categoriesViewModel.getSubcategoriesForCategory(categoryId)
        
        // Добавляем выбранные подкатегории, которые могут быть не привязаны к категории
        let selectedSubcategories = categoriesViewModel.subcategories.filter { selectedSubcategoryIds.contains($0.id) }
        
        // Объединяем и убираем дубликаты
        var allSubcategories = linkedSubcategories
        for selected in selectedSubcategories {
            if !allSubcategories.contains(where: { $0.id == selected.id }) {
                allSubcategories.append(selected)
            }
        }
        
        return allSubcategories
    }
    
    var body: some View {
        if !availableSubcategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(availableSubcategories) { subcategory in
                        FilterChip(
                            title: subcategory.name,
                            isSelected: selectedSubcategoryIds.contains(subcategory.id),
                            onTap: {
                                if selectedSubcategoryIds.contains(subcategory.id) {
                                    selectedSubcategoryIds.remove(subcategory.id)
                                } else {
                                    selectedSubcategoryIds.insert(subcategory.id)
                                    // Автоматически привязываем к категории, если еще не привязана
                                    if let categoryId = categoryId {
                                        categoriesViewModel.linkSubcategoryToCategory(
                                            subcategoryId: subcategory.id,
                                            categoryId: categoryId
                                        )
                                    }
                                }
                                HapticManager.selection()
                            }
                        )
                    }
                    
                    // Кнопка поиска справа
                    Button(action: onSearchTap) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: AppIconSize.sm))
                    }
                    .filterChipStyle()
                    .accessibilityLabel(String(localized: "transactionForm.searchSubcategories"))
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .scrollClipDisabled()
        } else {
            // Если нет подкатегорий, показываем только кнопку поиска на всю ширину
            Button(action: onSearchTap) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppIconSize.sm))
                    Text(String(localized: "transactionForm.addSubcategory"))
                }
            }
            .filterChipStyle()
            .accessibilityLabel(String(localized: "transactionForm.addSubcategory"))
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

#Preview {
    @Previewable @State var selectedIds: Set<String> = []
    let coordinator = AppCoordinator()
    
    return VStack {
        SubcategorySelectorView(
            categoriesViewModel: coordinator.categoriesViewModel,
            categoryId: nil,
            selectedSubcategoryIds: $selectedIds,
            onSearchTap: {
            }
        )
    }
    .padding()
}
