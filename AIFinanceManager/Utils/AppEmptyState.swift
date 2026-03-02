//
//  AppEmptyState.swift
//  AIFinanceManager
//
//  Консистентный empty state / error state компонент
//

import SwiftUI

/// Единый компонент для отображения empty states И error states.
///
/// **Когда какой стиль использовать:**
/// | Style     | Контекст                                         | Иконка     | Цвет       | CTA          |
/// |-----------|--------------------------------------------------|------------|------------|--------------|
/// | `.standard` | Management screens (нет данных, создай первый) | secondary  | нейтральный | optional     |
/// | `.compact`  | Card-контекст на home screen                   | нет        | нейтральный | нет          |
/// | `.error`    | Ошибка загрузки, сетевая ошибка, сбой импорта  | destructive | красный    | "Повторить"  |
///
/// Usage:
/// ```swift
/// // Empty state
/// EmptyStateView(
///     icon: "doc.text.magnifyingglass",
///     title: "Нет операций",
///     description: "Добавьте первую операцию"
/// )
///
/// // Error state с retry
/// EmptyStateView(
///     icon: "wifi.slash",
///     title: "Нет соединения",
///     description: "Проверьте интернет и попробуйте снова",
///     actionTitle: "Повторить",
///     action: { viewModel.reload() },
///     style: .error
/// )
/// ```
struct EmptyStateView: View {

    /// Визуальный стиль empty / error state
    enum Style {
        /// Полный — иконка + текст + optional action button. Для management screens.
        case standard
        /// Компактный — только текст, без иконки и action. Для card-контекстов на home screen.
        case compact
        /// Ошибка — иконка `exclamationmark.triangle` + красный текст + optional retry action.
        /// Используй когда загрузка данных провалилась или произошёл сбой.
        case error
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
        case .error:
            errorBody
        }
    }

    // MARK: - Standard Body

    private var standardBody: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon.isEmpty ? "tray" : icon)
                .font(.system(size: AppIconSize.xxxl))
                .foregroundStyle(.secondary)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h4)
                    .foregroundStyle(.secondary)

                if let description = description {
                    Text(description)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .secondaryButton()
                .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxxl)
    }

    // MARK: - Compact Body

    private var compactBody: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.secondary)

            if let description = description {
                Text(description)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
    }

    // MARK: - Error Body

    private var errorBody: some View {
        VStack(spacing: AppSpacing.lg) {
            // Иконка ошибки — если передана custom, используем её; fallback → exclamationmark.triangle
            Image(systemName: icon.isEmpty ? "exclamationmark.triangle" : icon)
                .font(.system(size: AppIconSize.xxxl))
                .foregroundStyle(AppColors.destructive)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.destructive)

                if let description = description {
                    Text(description)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondaryAccessible)
                        .multilineTextAlignment(.center)
                }
            }

            // Retry / action кнопка
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text(actionTitle)
                    }
                }
                .secondaryButton()
                .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description ?? "")")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Preview

#Preview("Standard & Compact") {
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

#Preview("Error State") {
    VStack(spacing: 40) {
        // Ошибка с retry
        EmptyStateView(
            icon: "wifi.slash",
            title: "Нет соединения",
            description: "Проверьте интернет и попробуйте снова",
            actionTitle: "Повторить",
            action: {},
            style: .error
        )

        // Ошибка без retry (критическая)
        EmptyStateView(
            icon: "exclamationmark.octagon",
            title: "Ошибка загрузки",
            description: "Данные повреждены. Обратитесь в поддержку.",
            style: .error
        )
    }
}
