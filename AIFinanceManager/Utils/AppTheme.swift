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
    /// 2pt - Минимальный отступ (tight inline spacing, fine-tuned layouts)
    static let xxs: CGFloat = 2

    /// 4pt - Микро отступ (между иконкой и текстом в одной строке)
    static let xs: CGFloat = 4

    /// 6pt - Компактный отступ (tight button padding, small chip padding)
    static let compact: CGFloat = 6

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

    // MARK: - Semantic Spacing

    /// Горизонтальный padding для страниц (alias для lg)
    static let pageHorizontal: CGFloat = lg

    /// Вертикальный spacing между секциями страницы (alias для xxl)
    static let sectionVertical: CGFloat = xxl

    /// Padding внутри карточек (alias для md)
    static let cardPadding: CGFloat = md

    /// Spacing между элементами в списке (alias для sm)
    static let listRowSpacing: CGFloat = sm

    /// Spacing между иконкой и текстом inline (alias для xs)
    static let iconText: CGFloat = xs

    /// Spacing между label и value в InfoRow (alias для md)
    static let labelValue: CGFloat = md
}

// MARK: - Corner Radius System

/// Консистентная система скругления углов
enum AppRadius {
    /// 4pt - Минимальные элементы (indicators, badges)
    static let xs: CGFloat = 4

    /// 6pt - Очень малые элементы (compact chips)
    static let compact: CGFloat = 6

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

    // MARK: - Semantic Radius

    /// Card corner radius (alias для md)
    static let card: CGFloat = md

    /// Button corner radius (alias для md)
    static let button: CGFloat = md

    /// Sheet corner radius (alias для lg)
    static let sheet: CGFloat = lg

    /// Chip corner radius (alias для sm)
    static let chip: CGFloat = sm
}

// MARK: - Icon Sizing System

/// Консистентная система размеров иконок
enum AppIconSize {
    /// 12pt - Micro icons (tiny indicators, badges)
    static let xs: CGFloat = 12

    /// 14pt - Small indicators (dots, small badges)
    static let indicator: CGFloat = 14

    /// 16pt - Inline icons (в тексте, мелкие индикаторы)
    static let sm: CGFloat = 16

    /// 20pt - Default icons (toolbar, списки)
    static let md: CGFloat = 20

    /// 24pt - Emphasized icons (category icons в списках)
    static let lg: CGFloat = 24

    /// 32pt - Large icons (bank logos)
    static let xl: CGFloat = 32

    /// 40pt - Medium avatar size (logo picker, subscription icons)
    static let avatar: CGFloat = 40

    /// 44pt - Extra large (category circles в QuickAdd)
    static let xxl: CGFloat = 44

    /// 48pt - Hero icons (empty states)
    static let xxxl: CGFloat = 48

    /// 52pt - Category row icons
    static let categoryIcon: CGFloat = 52

    /// 56pt - Floating action buttons
    static let fab: CGFloat = 56

    /// 64pt - Category coins
    static let coin: CGFloat = 64

    /// 72pt - Budget ring (coin + 8pt stroke space)
    static let budgetRing: CGFloat = 72

    /// 80pt - Large action buttons (voice input button)
    static let largeButton: CGFloat = 80
}

// MARK: - Inter Font Helper

/// Centralizes Inter variable font family name (as registered in UIAppFonts).
/// Weight axis (wght 100–900) is set via .weight() modifier.
/// Optical size axis (opsz) is set automatically from pointSize.
/// Verify with: UIFont.fontNames(forFamilyName: "Inter")
private enum AppInterFont {
    static let family = "Inter"
}

// MARK: - Typography System

/// Консистентная система типографики с уровнями.
/// Использует Inter variable font (Google Fonts, SIL OFL) с Dynamic Type.
/// Ось opsz применяется автоматически — iOS передаёт pointSize как значение opsz.
/// Веса задаются через .weight(), который маппируется на ось wght (100–900).
enum AppTypography {
    // MARK: Headers

    /// H1 - Screen titles (34pt bold, scales with largeTitle)
    static let h1 = Font.custom(AppInterFont.family, size: 34, relativeTo: .largeTitle).weight(.bold)

    /// H2 - Major section titles (28pt semibold, scales with title)
    static let h2 = Font.custom(AppInterFont.family, size: 28, relativeTo: .title).weight(.semibold)

    /// H3 - Card headers, modal titles (24pt semibold, scales with title2)
    static let h3 = Font.custom(AppInterFont.family, size: 24, relativeTo: .title2).weight(.semibold)

    /// H4 - Row titles, list item headers (20pt semibold, scales with title3)
    static let h4 = Font.custom(AppInterFont.family, size: 20, relativeTo: .title3).weight(.semibold)

    // MARK: Body Text

    /// Body Large - Emphasized body text (18pt medium, scales with body)
    static let bodyLarge = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.medium)

    /// Body - Default text (18pt regular, scales with body)
    static let body = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.regular)

    /// Body Small - Secondary text (16pt regular, scales with subheadline)
    static let bodySmall = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.regular)

    // MARK: Captions

    /// Caption - Helper text, timestamps, metadata (14pt regular, scales with caption)
    static let caption = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.regular)

    /// Caption Emphasis - Important helper text (14pt medium, scales with caption)
    static let captionEmphasis = Font.custom(AppInterFont.family, size: 14, relativeTo: .caption).weight(.medium)

    /// Caption 2 - Very small text (12pt regular, scales with caption2)
    static let caption2 = Font.custom(AppInterFont.family, size: 12, relativeTo: .caption2).weight(.regular)

    // MARK: - Semantic Typography

    /// Screen titles (alias для h1)
    static let screenTitle = h1

    /// Section headers (alias для captionEmphasis)
    static let sectionHeader = captionEmphasis

    /// Primary body text (alias для body)
    static let bodyPrimary = body

    /// Secondary text (alias для bodySmall)
    static let bodySecondary = bodySmall

    /// Label text (16pt medium, scales with subheadline)
    static let label = Font.custom(AppInterFont.family, size: 16, relativeTo: .subheadline).weight(.medium)

    /// Amount text (18pt semibold, scales with body)
    static let amount = Font.custom(AppInterFont.family, size: 18, relativeTo: .body).weight(.semibold)
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

    /// Фон primary экрана
    static let backgroundPrimary = Color(.systemBackground)

    /// Фон surface (карточки, elevated elements)
    static let surface = Color(.secondarySystemBackground)

    /// Фон основных карточек (alias для surface)
    static let cardBackground = surface

    /// Фон вторичных элементов (chips, secondary buttons)
    static let secondaryBackground = Color(.systemGray5)

    /// Фон экрана (alias для backgroundPrimary)
    static let screenBackground = backgroundPrimary

    // MARK: Text Colors

    /// Primary text (используй системный .primary для auto light/dark)
    static let textPrimary = Color.primary

    /// Secondary text (используй системный .secondary для auto light/dark)
    static let textSecondary = Color.secondary

    /// Tertiary text (используй системный .gray для мета-информации)
    static let textTertiary = Color.gray

    // MARK: Interactive Colors

    /// Accent color (для выделений, selections)
    static let accent = Color.blue

    /// Destructive actions
    static let destructive = Color.red

    /// Success/positive
    static let success = Color.green

    /// Warning
    static let warning = Color.orange

    // MARK: Dividers & Borders

    /// Divider color
    static let divider = Color(.separator)

    /// Border color
    static let border = Color(.systemGray4)

    // MARK: Transaction Type Colors (semantic)

    /// Income transactions
    static let income = Color.green

    /// Expense transactions
    static let expense = Color.primary

    /// Transfer transactions
    static let transfer = Color.primary
}

// MARK: - View Modifiers для консистентного применения

extension View {
    /// Применяет стандартный стиль карточки
    /// - Parameters:
    ///   - radius: Corner radius (по умолчанию .md)
    ///   - padding: Внутренний padding (по умолчанию .md)
    func cardStyle(radius: CGFloat = AppRadius.pill, padding: CGFloat = AppSpacing.md) -> some View {
        self
            .padding(padding)
            .background(AppColors.cardBackground)
            .clipShape(.rect(cornerRadius: radius))
    }

    /// Применяет стандартный стиль для list row
    func rowStyle() -> some View {
        self
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
    }

    /// Применяет стиль chip (используется для CategoryChip, general purpose chips)
    /// - Parameter isSelected: Если true, применяет выделенный стиль (accent background)
    func chipStyle(isSelected: Bool = false) -> some View {
        self
            .font(AppTypography.label)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.accent.opacity(0.2) : AppColors.secondaryBackground)
            .clipShape(.rect(cornerRadius: AppRadius.pill))
    }

    /// Применяет стандартный стиль для фильтров с glass effect (FilterChip, AccountFilterMenu, CategoryFilterButton)
    /// Использует iOS 26+ glass morphism API для современного вида с fallback для iOS 25 и ранее
    /// - Parameter isSelected: Если true, применяет выделенный стиль (accent tint + glass effect)
    @ViewBuilder
    func filterChipStyle(isSelected: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: AppRadius.pill))
                .glassEffect(
                    isSelected
                    ? .regular.tint(AppColors.accent.opacity(0.2)).interactive()
                    : .regular.interactive()
                )
        } else {
            self
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isSelected
                    ? AppColors.accent.opacity(0.2)
                    : AppColors.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: AppRadius.pill)
                )
        }
    }

    /// Применяет тень
    func shadowStyle(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    /// Применяет glass effect с стандартным cornerRadius для карточек (iOS 26+)
    /// Автоматически добавляет padding и contentShape с fallback для iOS 25 и ранее
    /// - Parameter radius: Corner radius (по умолчанию .pill)
    @ViewBuilder
    func glassCardStyle(radius: CGFloat = AppRadius.pill) -> some View {
        if #available(iOS 26, *) {
            self
                .padding(AppSpacing.lg)
                .contentShape(Rectangle())
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .padding(AppSpacing.lg)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }
    
    /// Применяет glass/material background без clipShape поверх контента.
    /// Используется для карточек с встроенными Swift Charts — clipShape обрезает Metal-слои Charts.
    /// На iOS 26+ glassEffect сам обрезает glass по форме, не затрагивая SwiftUI-контент.
    /// - Parameter radius: Corner radius (по умолчанию .pill)
    @ViewBuilder
    func cardBackground(radius: CGFloat = AppRadius.pill) -> some View {
        if #available(iOS 26, *) {
            // ⚠️ Намеренно НЕ применяем clipShape — он обрезает Swift Charts слои.
            // glassEffect(in: .rect(cornerRadius:)) самостоятельно задаёт форму glass-слоя.
            self
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
                .clipShape(.rect(cornerRadius: radius))
        }
    }

    /// Применяет стиль для fallback иконок (используется в BrandLogoView, SubscriptionCard)
    /// - Parameter size: Размер иконки
    func fallbackIconStyle(size: CGFloat) -> some View {
        self
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - Layout Helpers

extension View {
    /// Стандартный horizontal padding для экранов
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.pageHorizontal)
    }

    /// Стандартный vertical spacing для sections
    func sectionSpacing() -> some View {
        self.padding(.vertical, AppSpacing.sectionVertical)
    }

    /// Card padding (внутренний padding карточек)
    func cardContentPadding() -> some View {
        self.padding(AppSpacing.cardPadding)
    }

    /// List row padding (padding для строк списка)
    func listRowPadding() -> some View {
        self.padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, AppSpacing.listRowSpacing)
    }
}

// MARK: - Transaction Row Styles

/// Варианты стилизации строк транзакций
enum TransactionRowVariant {
    /// Стандартный стиль с фоном
    case standard
    /// Прозрачный фон
    case transparent
    /// Карточный стиль с тенью
    case card
}

extension View {
    /// Стилизует view как строку транзакции
    /// - Parameters:
    ///   - isPlanned: Является ли транзакция плановой (будет синий фон)
    ///   - variant: Вариант стилизации
    func transactionRowStyle(
        isPlanned: Bool = false,
        variant: TransactionRowVariant = .standard
    ) -> some View {
        self
            .padding(AppSpacing.sm)
            .background(backgroundForVariant(isPlanned: isPlanned, variant: variant))
            .clipShape(.rect(cornerRadius: AppRadius.sm))
    }

    /// Вычисляет фон для заданного варианта стилизации
    private func backgroundForVariant(isPlanned: Bool, variant: TransactionRowVariant) -> Color {
        if isPlanned {
            // Для плановых транзакций всегда синий оттенок
            return Color.blue.opacity(0.1)
        }

        switch variant {
        case .standard:
            return AppColors.secondaryBackground
        case .transparent:
            return .clear
        case .card:
            return AppColors.surface
        }
    }

    /// Phase 16: Liquid Glass стиль для карточек транзакций (iOS 26+)
    /// Применяет glassEffect на iOS 26+, стандартный фон на более ранних версиях.
    /// - Parameters:
    ///   - isPlanned: Плановая транзакция (синий оттенок на обеих платформах)
    ///   - radius: Corner radius (по умолчанию .sm для строк)
    @ViewBuilder
    func glassTransactionRowStyle(
        isPlanned: Bool = false,
        radius: CGFloat = AppRadius.sm
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(
                    isPlanned
                        ? .regular.tint(.blue.opacity(0.12))
                        : .regular,
                    in: .rect(cornerRadius: radius)
                )
        } else {
            self
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isPlanned ? Color.blue.opacity(0.1) : AppColors.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }
}

// MARK: - Container Sizes

/// Консистентные размеры контейнеров и макет-элементов
enum AppSize {
    // MARK: - Buttons & Controls

    /// Small button size (40x40)
    static let buttonSmall: CGFloat = 40

    /// Medium button size (56x56)
    static let buttonMedium: CGFloat = 56

    /// Large button size (64x64)
    static let buttonLarge: CGFloat = 64

    /// Extra large button size (80x80)
    static let buttonXL: CGFloat = 80

    // MARK: - Cards & Containers

    /// Subscription card width
    static let subscriptionCardWidth: CGFloat = 120

    /// Subscription card height
    static let subscriptionCardHeight: CGFloat = 80

    /// Analytics card skeleton width
    static let analyticsCardWidth: CGFloat = 200

    /// Analytics card skeleton height
    static let analyticsCardHeight: CGFloat = 140

    // MARK: - Scroll & List Constraints

    /// Max height for scrollable preview sections
    static let previewScrollHeight: CGFloat = 300

    /// Max height for result lists
    static let resultListHeight: CGFloat = 150

    /// Min height for content sections
    static let contentMinHeight: CGFloat = 120

    /// Standard height for rows/cells
    static let rowHeight: CGFloat = 60

    // MARK: - Specific UI Elements

    /// Calendar picker width
    static let calendarPickerWidth: CGFloat = 180

    /// Wave animation height (small)
    static let waveHeightSmall: CGFloat = 80

    /// Wave animation height (medium)
    static let waveHeightMedium: CGFloat = 100

    /// Skeleton placeholder height
    static let skeletonHeight: CGFloat = 16

    /// Cursor line width
    static let cursorWidth: CGFloat = 2

    /// Cursor line height for numeric amount input
    static let cursorHeight: CGFloat = 36

    /// Cursor line height for large title input (h1)
    static let cursorHeightLarge: CGFloat = 44
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

    /// Spring animation для bounce эффекта (iOS 16+ style)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
}

// MARK: - Interactive Button Styles

/// Интерактивный стиль кнопки с эффектом увеличения и bounce (iOS 16+ style)
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0.0)
            .animation(AppAnimation.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BounceButtonStyle {
    /// Применяет iOS 16+ стиль с эффектом увеличения и bounce при нажатии
    static var bounce: BounceButtonStyle {
        BounceButtonStyle()
    }
}
