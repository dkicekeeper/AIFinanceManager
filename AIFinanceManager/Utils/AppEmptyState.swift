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

    /// Визуальный стиль empty state
    enum Style {
        /// Полный — иконка + текст + optional action button. Для management screens.
        case standard
        /// Компактный — только текст, без иконки и action. Для card-контекстов на home screen.
        case compact
    }

    let icon: String
    let title: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let style: Style

    init(
        icon: String = "",
        title: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        style: Style = .standard
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
        self.style = style
    }

    var body: some View {
        switch style {
        case .standard:
            standardBody
        case .compact:
            compactBody
        }
    }

    private var standardBody: some View {
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

    private var compactBody: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)

            if let description = description {
                Text(description)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
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
