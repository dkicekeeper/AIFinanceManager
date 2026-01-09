//
//  CategoriesManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CategoriesManagementView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: TransactionType = .expense
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Фильтр по типу
                Picker("Type", selection: $selectedType) {
                    Text("Расходы").tag(TransactionType.expense)
                    Text("Доходы").tag(TransactionType.income)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width > 50 {
                                // Свайп вправо - переключить на предыдущий
                                if selectedType == .income {
                                    selectedType = .expense
                                }
                            } else if value.translation.width < -50 {
                                // Свайп влево - переключить на следующий
                                if selectedType == .expense {
                                    selectedType = .income
                                }
                            }
                        }
                )
                
                // Список категорий
                List {
                    ForEach(filteredCategories) { category in
                        CategoryRow(
                            category: category,
                            isDefault: false,
                            onEdit: { 
                                editingCategory = category
                            },
                            onDelete: { 
                                viewModel.deleteCategory(category)
                            }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Готово") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddCategory = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryEditView(
                    viewModel: viewModel,
                    category: nil,
                    type: selectedType,
                    onSave: { category in
                        viewModel.addCategory(category)
                        showingAddCategory = false
                    },
                    onCancel: { showingAddCategory = false }
                )
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditView(
                    viewModel: viewModel,
                    category: category,
                    type: category.type,
                    onSave: { updatedCategory in
                        viewModel.updateCategory(updatedCategory)
                        editingCategory = nil
                    },
                    onCancel: { editingCategory = nil }
                )
            }
        }
    }
    
    private var filteredCategories: [CustomCategory] {
        // Только пользовательские категории (исключая скрытые)
        return viewModel.customCategories
            .filter { $0.type == selectedType && !$0.name.hasPrefix("_hidden_") }
            .sorted { $0.name < $1.name }
    }
}

struct CategoryRow: View {
    let category: CustomCategory
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка
            Circle()
                .fill(category.color.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: category.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(category.color)
                )
                .overlay(
                    Circle()
                        .stroke(category.color, lineWidth: 2)
                )
            
            // Название
            Text(category.name)
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
            if !isDefault {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct CategoryEditView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let category: CustomCategory?
    let type: TransactionType
    let onSave: (CustomCategory) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var iconName: String = "banknote.fill"
    @State private var selectedColor: String = "#3b82f6"
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var showingSubcategoryPicker = false
    
    private let defaultColors: [String] = [
        "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
        "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
        "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
    ]
    
    private let commonIcons: [String] = [
        "banknote.fill", "hamburger.fill", "car.fill", "bag.fill", "sparkles", "lightbulb.fill", "cross.case.fill", "graduationcap.fill",
        "dollar.circle.fill", "briefcase.fill", "box.fill", "gift.fill", "airplane.fill", "cart.fill", "cup.and.saucer.fill", "tv.fill",
        "house.fill", "car.fill", "fork.knife", "film.fill", "iphone", "laptopcomputer", "gamecontroller.fill", "dumbbell.fill"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Название")) {
                    TextField("Название категории", text: $name)
                }
                
                Section(header: Text("Иконка")) {
                    HStack {
                        Button(action: { showingIconPicker.toggle() }) {
                            Image(systemName: iconName)
                                .font(.system(size: 30))
                                .foregroundColor(hexToColor(selectedColor))
                                .frame(width: 60, height: 60)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        
                        Text("Нажмите для выбора")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Цвет")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(defaultColors, id: \.self) { colorHex in
                                Button(action: { selectedColor = colorHex }) {
                                    Circle()
                                        .fill(hexToColor(colorHex))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColor == colorHex ? 3 : 0)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Подкатегории
                if let category = category {
                    Section(header: Text("Подкатегории")) {
                        let categoryId = category.id
                        let linkedSubcategories = viewModel.getSubcategoriesForCategory(categoryId)
                        
                        ForEach(linkedSubcategories) { subcategory in
                            HStack {
                                Text(subcategory.name)
                                Spacer()
                                Button(action: {
                                    viewModel.unlinkSubcategoryFromCategory(subcategoryId: subcategory.id, categoryId: categoryId)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button(action: { showingSubcategoryPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Добавить подкатегорию")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSubcategoryPicker) {
                SubcategoryPickerView(
                    viewModel: viewModel,
                    categoryId: category?.id ?? "",
                    onSelect: { subcategoryId in
                        if let categoryId = category?.id {
                            viewModel.linkSubcategoryToCategory(subcategoryId: subcategoryId, categoryId: categoryId)
                        }
                        showingSubcategoryPicker = false
                    }
                )
            }
            .navigationTitle(category == nil ? "Новая категория" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        let newCategory = CustomCategory(
                            id: category?.id ?? UUID().uuidString,
                            name: name,
                            iconName: iconName,
                            colorHex: selectedColor,
                            type: type
                        )
                        onSave(newCategory)
                    }
                    .disabled(name.isEmpty || iconName.isEmpty)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIconName: $iconName)
            }
            .onAppear {
                if let category = category {
                    name = category.name
                    iconName = category.iconName
                    selectedColor = category.colorHex
                }
            }
        }
    }
    
    private func hexToColor(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
}

struct IconPickerView: View {
    @Binding var selectedIconName: String
    @Environment(\.dismiss) var dismiss
    
    private let iconCategories: [(String, [String])] = [
        ("Часто используемые", ["banknote.fill", "hamburger.fill", "car.fill", "bag.fill", "sparkles", "lightbulb.fill", "cross.case.fill", "graduationcap.fill", "dollar.circle.fill", "briefcase.fill", "box.fill", "gift.fill", "airplane.fill", "cart.fill", "cup.and.saucer.fill", "tv.fill"]),
        ("Еда", ["fork.knife", "hamburger.fill", "cup.and.saucer.fill", "cart.fill", "wineglass.fill", "birthday.cake.fill", "apple.fill", "leaf.fill"]),
        ("Транспорт", ["car.fill", "bus.fill", "airplane.fill", "tram.fill", "bicycle.circle.fill", "scooter", "ship.fill", "fuelpump.fill"]),
        ("Покупки", ["bag.fill", "cart.fill", "creditcard.fill", "handbag.fill", "tshirt.fill", "shoe.fill", "iphone", "laptopcomputer"]),
        ("Развлечения", ["film.fill", "gamecontroller.fill", "music.note", "theatermasks.fill", "paintpalette.fill", "book.fill", "sportscourt.fill", "dumbbell.fill"]),
        ("Здоровье", ["cross.case.fill", "pills.fill", "figure.run", "figure.yoga", "syringe", "face.smiling.fill", "eye", "heart.fill"]),
        ("Дом", ["house.fill", "key.fill", "chair.fill", "bed.double", "shower.fill", "flame.fill", "sparkles", "leaf.fill"]),
        ("Деньги", ["banknote.fill", "dollar.circle.fill", "creditcard.fill", "diamond.circle.fill", "building.columns.fill", "chart.bar.fill", "banknote.fill", "dollarsign.circle.fill"])
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(iconCategories, id: \.0) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.0)
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                                ForEach(category.1, id: \.self) { iconName in
                                    Button(action: {
                                        selectedIconName = iconName
                                        dismiss()
                                    }) {
                                        Image(systemName: iconName)
                                            .font(.system(size: 24))
                                            .foregroundColor(.primary)
                                            .frame(width: 50, height: 50)
                                            .background(selectedIconName == iconName ? Color.blue.opacity(0.2) : Color(.systemGray6))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Выберите иконку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CategoriesManagementView(viewModel: TransactionsViewModel())
}
