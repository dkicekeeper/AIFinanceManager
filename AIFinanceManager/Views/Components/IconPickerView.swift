//
//  IconPickerView.swift
//  AIFinanceManager
//
//  Reusable icon picker component for category icon selection
//

import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIconName: String
    @Environment(\.dismiss) var dismiss
    
    private let iconCategories: [(String, [String])] = [
        (String(localized: "iconPicker.frequentlyUsed"), ["banknote.fill", "cart.fill", "car.fill", "bag.fill", "fork.knife", "house.fill", "briefcase.fill", "heart.fill", "airplane", "gift.fill", "creditcard.fill", "tv.fill", "book.fill", "star.fill", "bolt.fill", "flame.fill"]),
        (String(localized: "iconPicker.foodAndDrinks"), ["fork.knife", "cup.and.saucer.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "fish.fill", "leaf.fill", "mug.fill"]),
        (String(localized: "iconPicker.transport"), ["car.fill", "bus.fill", "airplane", "tram.fill", "bicycle", "scooter", "ferry.fill", "fuelpump.fill"]),
        (String(localized: "iconPicker.shopping"), ["bag.fill", "cart.fill", "creditcard.fill", "handbag.fill", "tshirt.fill", "giftcard.fill", "basket.fill", "tag.fill"]),
        (String(localized: "iconPicker.entertainment"), ["film.fill", "gamecontroller.fill", "music.note", "theatermasks.fill", "paintpalette.fill", "book.fill", "sportscourt.fill", "figure.walk"]),
        (String(localized: "iconPicker.health"), ["cross.case.fill", "heart.text.square.fill", "bandage.fill", "syringe.fill", "cross.fill", "eye.fill", "waveform.path.ecg", "figure.run"]),
        (String(localized: "iconPicker.homeAndUtilities"), ["house.fill", "key.fill", "chair.fill", "bed.double.fill", "lightbulb.fill", "sparkles", "sofa.fill", "shower.fill"]),
        (String(localized: "iconPicker.moneyAndFinance"), ["banknote.fill", "dollarsign.circle.fill", "creditcard.fill", "building.columns.fill", "chart.bar.fill", "rublesign.circle.fill", "eurosign.circle.fill"])
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                    ForEach(iconCategories, id: \.0) { category in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            Text(category.0)
                                .font(AppTypography.h4)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, AppSpacing.lg)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.lg), count: 6),
                                spacing: AppSpacing.lg
                            ) {
                                ForEach(category.1, id: \.self) { iconName in
                                    Button(action: {
                                        HapticManager.selection()
                                        selectedIconName = iconName
                                        dismiss()
                                    }) {
                                        Image(systemName: iconName)
                                            .font(.system(size: AppIconSize.lg))
                                            .foregroundColor(selectedIconName == iconName ? .white : .primary)
                                            .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                                            .background(
                                                selectedIconName == iconName
                                                    ? Color.blue
                                                    : Color(.systemGray6)
                                            )
                                            .cornerRadius(AppRadius.lg)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.lg)
            }
            .navigationTitle(String(localized: "navigation.selectIcon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.done")) {
                        HapticManager.light()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedIcon = "banknote.fill"
    
    return IconPickerView(selectedIconName: $selectedIcon)
}
