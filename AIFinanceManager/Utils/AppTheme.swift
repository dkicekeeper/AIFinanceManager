//
//  AppTheme.swift
//  AIFinanceManager
//
//  Design System Lite - Single source of truth for UI consistency
//

import SwiftUI

// MARK: - Spacing System (4pt Grid)

/// Консистентная система отступов на основе 4pt grid
/// Используй ТОЛЬКО эти значения для всех spacing и padding
enum AppSpacing {
    /// 4pt - Микро отступ (между иконкой и текстом в одной строке)
    static let xs: CGFloat = 4

    /// 8pt - Малый отступ (vertical padding для rows, spacing внутри кнопок)
    static let sm: CGFloat = 8

    /// 12pt - Средний отступ (default VStack/HStack spacing, внутренний padding карточек)
    static let md: CGFloat = 12

    /// 16pt - Большой отступ (horizontal padding экранов, spacing между карточками)
    static let lg: CGFloat = 16

    /// 20pt - Очень большой отступ (spacing между major sections)
    static let xl: CGFloat = 20

    /// 24pt - Максимальный отступ (spacing между screen sections)
    static let xxl: CGFloat = 24

    /// 32pt - Screen margins (редко используется)
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius System

/// Консистентная система скругления углов
enum AppRadius {
    /// 8pt - Малые элементы (chips, небольшие кнопки)
    static let sm: CGFloat = 8

    /// 10pt - Стандартные карточки и кнопки (основной радиус)
    static let md: CGFloat = 10

    /// 12pt - Большие карточки
    static let lg: CGFloat = 12

    /// 20pt - Pills и filter chips
    static let pill: CGFloat = 20

    /// Бесконечность - Круги (category icons, avatars)
    static let circle: CGFloat = .infinity
}

// MARK: - Icon Sizing System

/// Консистентная система размеров иконок
enum AppIconSize {
    /// 16pt - Inline icons (в тексте, мелкие индикаторы)
    static let sm: CGFloat = 16

    /// 20pt - Default icons (toolbar, списки)
    static let md: CGFloat = 20

    /// 24pt - Emphasized icons (category icons в списках)
    static let lg: CGFloat = 24

    /// 32pt - Large icons (bank logos)
    static let xl: CGFloat = 32

    /// 44pt - Extra large (category circles в QuickAdd)
    static let xxl: CGFloat = 44

    /// 48pt - Hero icons (empty states)
    static let xxxl: CGFloat = 48

    /// 56pt - Floating action buttons
    static let fab: CGFloat = 56

    /// 64pt - Category coins
    static let coin: CGFloat = 64
}

// MARK: - Typography System

/// Консистентная система типографики с уровнями
enum AppTypography {
    // MARK: Headers

    /// H1 - Screen titles (используется через .navigationTitle, не напрямую)
    static let h1 = Font.largeTitle.weight(.bold)

    /// H2 - Major section titles
    static let h2 = Font.title.weight(.semibold)

    /// H3 - Card headers, modal titles
    static let h3 = Font.title2.weight(.semibold)

    /// H4 - Row titles, list item headers
    static let h4 = Font.title3.weight(.semibold)

    // MARK: Body Text

    /// Body Large - Emphasized body text (amounts, important info)
    static let bodyLarge = Font.body.weight(.medium)

    /// Body - Default text (descriptions, labels)
    static let body = Font.body

    /// Body Small - Secondary text (account names, dates)
    static let bodySmall = Font.subheadline

    // MARK: Captions

    /// Caption - Helper text, timestamps, metadata
    static let caption = Font.caption

    /// Caption Emphasis - Important helper text
    static let captionEmphasis = Font.caption.weight(.medium)

    /// Caption 2 - Very small text (legal, footnotes)
    static let caption2 = Font.caption2
}

// MARK: - Shadow System

/// Консистентная система теней
enum AppShadow {
    /// Нет тени
    static let none = Shadow(color: .clear, radius: 0, x: 0, y: 0)

    /// Малая тень (hover states, небольшая глубина)
    static let sm = Shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

    /// Средняя тень (cards, buttons)
    static let md = Shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

    /// Большая тень (floating buttons, modals)
    static let lg = Shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
}

// Вспомогательная структура для теней
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Semantic Colors

/// Семантические цвета приложения (дополняют существующую систему)
enum AppColors {
    // MARK: Backgrounds

    /// Фон основных карточек
    static let cardBackground = Color(.systemGray6)

    /// Фон вторичных элементов (chips, secondary buttons)
    static let secondaryBackground = Color(.systemGray5)

    /// Фон экрана
    static let screenBackground = Color(.systemBackground)

    // MARK: Text Colors (используй системные .primary, .secondary)

    // MARK: Semantic Colors (уже определены в CategoryColors)
    // income - .green
    // expense - .red
    // transfer - .blue
}

// MARK: - View Modifiers для консистентного применения

extension View {
    /// Применяет стандартный стиль карточки
    /// - Parameters:
    ///   - radius: Corner radius (по умолчанию .md)
    ///   - padding: Внутренний padding (по умолчанию .md)
    func cardStyle(radius: CGFloat = AppRadius.md, padding: CGFloat = AppSpacing.md) -> some View {
        self
            .padding(padding)
            .background(AppColors.cardBackground)
            .cornerRadius(radius)
    }

    /// Применяет стандартный стиль для list row
    func rowStyle() -> some View {
        self
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
    }

    /// Применяет стиль filter chip
    func chipStyle(isSelected: Bool = false) -> some View {
        self
            .font(AppTypography.bodySmall.weight(.medium))
            .foregroundColor(.primary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? Color.blue.opacity(0.2) : AppColors.secondaryBackground)
            .cornerRadius(AppRadius.pill)
    }
    
    /// Применяет стандартный стиль для фильтров (FilterChip, AccountFilterMenu, CategoryFilterButton)
    /// - Parameters:
    ///   - isSelected: Если true, применяет выделенный стиль (синий фон)
    func filterChipStyle(isSelected: Bool = false) -> some View {
        self
            .font(AppTypography.bodySmall)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray5))
            .cornerRadius(AppRadius.pill)
    }

    /// Применяет тень
    func shadowStyle(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    /// Применяет glass effect с стандартным cornerRadius для карточек
    /// - Parameter radius: Corner radius (по умолчанию .pill)
    func glassCardStyle(radius: CGFloat = AppRadius.pill) -> some View {
        self.glassEffect(in: .rect(cornerRadius: radius))
    }
    
    /// Применяет стиль для fallback иконок (используется в BrandLogoView, SubscriptionCard)
    /// - Parameter size: Размер иконки
    func fallbackIconStyle(size: CGFloat) -> some View {
        self
            .font(.system(size: size * 0.6))
            .foregroundColor(.secondary)
            .frame(width: size, height: size)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - Layout Helpers

extension View {
    /// Стандартный horizontal padding для экранов
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.lg)
    }

    /// Стандартный vertical spacing для sections
    func sectionSpacing() -> some View {
        self.padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Animation Durations

/// Консистентные длительности анимаций
enum AppAnimation {
    /// Быстрая анимация (button press, selection)
    static let fast: Double = 0.1

    /// Стандартная анимация (transitions, state changes)
    static let standard: Double = 0.25

    /// Медленная анимация (modals, large transitions)
    static let slow: Double = 0.35
}
