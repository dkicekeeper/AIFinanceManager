//
//  AppEmptyState.swift
//  AIFinanceManager
//
//  Консистентный empty state компонент
//

import SwiftUI

/// Единый компонент для отображения empty states
/// Используй когда: нет данных в списках, нет результатов поиска, нет категорий и т.д.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?

    /// Создаёт empty state view
    /// - Parameters:
    ///   - icon: SF Symbol название (например: "doc.text.magnifyingglass")
    ///   - title: Основной заголовок (например: "Нет операций")
    ///   - description: Опциональное описание (например: "Добавьте первую операцию")
    ///   - actionTitle: Опциональный текст кнопки действия
    ///   - action: Опциональное действие при нажатии на кнопку
    init(
        icon: String,
        title: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: AppIconSize.xxxl))
                .foregroundColor(.secondary)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h4)
                    .foregroundColor(.secondary)

                if let description = description {
                    Text(description)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .tertiaryButton()
                .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxl)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "Нет операций",
            description: "Добавьте первую операцию чтобы начать отслеживать финансы"
        )

        EmptyStateView(
            icon: "folder",
            title: "Нет категорий",
            description: nil,
            actionTitle: "Добавить категорию",
            action: {}
        )
    }
}
