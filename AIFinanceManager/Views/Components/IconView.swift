//
//  IconView.swift
//  AIFinanceManager
//
//  Unified icon and logo display component with full Design System integration
//  Created: 2026-02-12
//

import SwiftUI

/// Универсальный компонент для отображения иконок и логотипов
/// Полностью интегрирован с Design System (AppTheme.swift)
///
/// # Примеры использования:
///
/// ## SF Symbol с пресетом
/// ```swift
/// IconView(source: .sfSymbol("star.fill"), style: .categoryIcon())
/// ```
///
/// ## Банковский логотип с кастомным размером
/// ```swift
/// IconView(source: .bankLogo(.kaspi), style: .bankLogo(size: 40))
/// ```
///
/// ## Динамический логотип сервиса
/// ```swift
/// IconView(source: .brandService("netflix"), style: .serviceLogo())
/// ```
///
/// ## Полный контроль над стилем
/// ```swift
/// IconView(
///     source: .sfSymbol("heart.fill"),
///     style: .circle(
///         size: AppIconSize.xl,
///         tint: .monochrome(.red),
///         backgroundColor: AppColors.surface
///     )
/// )
/// ```
struct IconView: View {

    // MARK: - Properties

    let source: IconSource?
    let style: IconStyle

    // MARK: - Initializers

    init(source: IconSource?, style: IconStyle) {
        self.source = source
        self.style = style
    }

    /// Convenience initializer с автоматическим выбором стиля по типу источника
    /// - Parameters:
    ///   - source: Источник иконки (IconSource)
    ///   - size: Размер иконки (по умолчанию AppIconSize.xl из Design System)
    init(source: IconSource?, size: CGFloat = AppIconSize.xl) {
        self.source = source

        // Автоматический выбор стиля в зависимости от типа источника
        switch source {
        case .sfSymbol:
            self.style = .categoryIcon(size: size)
        case .bankLogo:
            self.style = .bankLogo(size: size)
        case .brandService:
            self.style = .serviceLogo(size: size)
        case .none:
            self.style = .placeholder(size: size)
        }
    }

    // MARK: - Body

    var body: some View {
        containerView {
            contentView
                .frame(width: contentSize, height: contentSize)
        }
    }

    // MARK: - Computed Properties

    /// Размер контента с учетом padding
    private var contentSize: CGFloat {
        if let padding = style.padding {
            return style.size - (padding * 2)
        }
        return style.size
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch source {
        case .sfSymbol(let name):
            sfSymbolView(name)

        case .bankLogo(let logo):
            bankLogoView(logo)

        case .brandService(let name):
            brandServiceView(name)

        case .none:
            placeholderView
        }
    }

    // MARK: - SF Symbol View

    @ViewBuilder
    private func sfSymbolView(_ symbolName: String) -> some View {
        let image = Image(systemName: symbolName)
            .resizable()
            .aspectRatio(contentMode: style.contentMode)

        // Применяем rendering mode в зависимости от tint
        switch style.tint {
        case .monochrome(let color):
            image
                .foregroundStyle(color)

        case .hierarchical(let color):
            if #available(iOS 15, *) {
                image
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            } else {
                image
                    .foregroundStyle(color)
            }

        case .palette(let colors):
            if #available(iOS 15, *) {
                applyPalette(to: image, colors: colors)
            } else {
                image
                    .foregroundStyle(colors.first ?? AppColors.accent)
            }

        case .original:
            image
                .foregroundStyle(AppColors.accent)
        }
    }

    @available(iOS 15, *)
    @ViewBuilder
    private func applyPalette(to image: some View, colors: [Color]) -> some View {
        switch colors.count {
        case 1:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0])
        case 2:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1])
        case 3...:
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(colors[0], colors[1], colors[2])
        default:
            image
                .foregroundStyle(AppColors.accent)
        }
    }

    // MARK: - Bank Logo View

    @ViewBuilder
    private func bankLogoView(_ logo: BankLogo) -> some View {
        if logo == .none {
            placeholderView
        } else if let uiImage = UIImage(named: logo.rawValue) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: style.contentMode)
        } else {
            placeholderView
        }
    }

    // MARK: - Brand Service View

    @ViewBuilder
    private func brandServiceView(_ brandName: String) -> some View {
        // Интегрируем BrandLogoView напрямую для унификации
        BrandLogoView(brandName: brandName, size: contentSize)
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        Image(systemName: "photo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(AppColors.textSecondary)
    }

    // MARK: - Container View

    @ViewBuilder
    private func containerView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let baseView = content()
            .frame(width: style.size, height: style.size)

        // Применяем фон если задан
        let viewWithBackground = Group {
            if let bgColor = style.backgroundColor {
                baseView.background(bgColor)
            } else {
                baseView
            }
        }

        // Применяем padding если задан
        let viewWithPadding = Group {
            if let padding = style.padding {
                viewWithBackground.padding(padding)
            } else {
                viewWithBackground
            }
        }

        // Применяем форму с обрезкой контента
        let viewWithShape = Group {
            switch style.shape {
            case .circle:
                viewWithPadding
                    .clipShape(Circle())
                    .contentShape(Circle())

            case .roundedSquare(let radius):
                viewWithPadding
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .contentShape(RoundedRectangle(cornerRadius: radius))

            case .square:
                viewWithPadding
                    .clipShape(Rectangle())
                    .contentShape(Rectangle())
            }
        }

        // Применяем glass effect если требуется
        if style.hasGlassEffect {
            if #available(iOS 18.0, *) {
                switch style.shape {
                case .circle:
                    viewWithShape
                        .glassEffect(in: Circle())
                case .roundedSquare(let radius):
                    viewWithShape
                        .glassEffect(in: RoundedRectangle(cornerRadius: radius))
                case .square:
                    viewWithShape
                        .glassEffect(in: Rectangle())
                }
            } else {
                // Fallback для более старых версий iOS
                viewWithShape
            }
        } else {
            viewWithShape
        }
    }
}

// MARK: - Previews

#Preview("Design System Presets") {
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            PresetSection(
                title: "Category Icons",
                examples: [
                    (.sfSymbol("star.fill"), IconStyle.categoryIcon()),
                    (.sfSymbol("cart.fill"), IconStyle.categoryIcon()),
                    (.sfSymbol("heart.fill"), IconStyle.categoryCoin())
                ]
            )

            PresetSection(
                title: "Bank Logos",
                examples: [
                    (.bankLogo(.kaspi), IconStyle.bankLogo()),
                    (.bankLogo(.halykBank), IconStyle.bankLogo(size: AppIconSize.avatar)),
                    (.bankLogo(.tbank), IconStyle.bankLogoLarge())
                ]
            )

            PresetSection(
                title: "Service Logos",
                examples: [
                    (.brandService("netflix"), IconStyle.serviceLogo()),
                    (.brandService("spotify"), IconStyle.serviceLogo(size: AppIconSize.avatar)),
                    (.brandService("notion"), IconStyle.serviceLogoLarge())
                ]
            )

            PresetSection(
                title: "Utility Icons",
                examples: [
                    (.sfSymbol("gear"), IconStyle.toolbar()),
                    (.sfSymbol("plus"), IconStyle.inline()),
                    (.sfSymbol("photo"), IconStyle.emptyState())
                ]
            )

            PlaceholderSection()
        }
        .padding(AppSpacing.lg)
    }
}

#Preview("Shapes") {
    VStack(spacing: AppSpacing.xl) {
        ShapeRow(
            title: String(localized: "iconStyle.shape.circle"),
            style: .circle(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        ShapeRow(
            title: String(localized: "iconStyle.shape.roundedSquare"),
            style: .roundedSquare(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        ShapeRow(
            title: String(localized: "iconStyle.shape.square"),
            style: .square(size: AppIconSize.xl, tint: .accentMonochrome)
        )
    }
    .padding(AppSpacing.lg)
}

#Preview("Tints") {
    VStack(spacing: AppSpacing.xl) {
        TintRow(
            title: String(localized: "iconStyle.tint.monochrome"),
            style: .circle(size: AppIconSize.xl, tint: .accentMonochrome)
        )

        TintRow(
            title: String(localized: "iconStyle.tint.hierarchical"),
            style: .circle(size: AppIconSize.xl, tint: .hierarchical(AppColors.accent))
        )

        if #available(iOS 15, *) {
            TintRow(
                title: String(localized: "iconStyle.tint.palette"),
                style: .circle(size: AppIconSize.xl, tint: .palette([.blue, .green, .red]))
            )
        }
    }
    .padding(AppSpacing.lg)
}

#Preview("Size Comparison") {
    VStack(spacing: AppSpacing.xl) {
        HStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.sm)
                Text("Small")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.md)
                Text("Medium")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.lg)
                Text("Large")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: AppSpacing.xs) {
                IconView(source: .sfSymbol("star.fill"), size: AppIconSize.xl)
                Text("XL")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
    .padding(AppSpacing.lg)
}

#Preview("Glass Effect") {
    if #available(iOS 18.0, *) {
        VStack(spacing: AppSpacing.xxl) {
            VStack(spacing: AppSpacing.md) {
                Text("Glass Hero (Circle)")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(source: .sfSymbol("tv.fill"), style: .glassHero())
                    IconView(source: .sfSymbol("music.note"), style: .glassHero())
                    IconView(source: .sfSymbol("cloud.fill"), style: .glassHero())
                }
            }

            VStack(spacing: AppSpacing.md) {
                Text("Glass Service (Rounded Square)")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(source: .brandService("netflix"), style: .glassService())
                    IconView(source: .brandService("spotify"), style: .glassService())
                    IconView(source: .brandService("notion"), style: .glassService())
                }
            }

            VStack(spacing: AppSpacing.md) {
                Text("Custom Glass Effect")
                    .font(AppTypography.h4)

                HStack(spacing: AppSpacing.lg) {
                    IconView(
                        source: .sfSymbol("star.fill"),
                        style: .circle(size: AppIconSize.xl, tint: .accentMonochrome, hasGlassEffect: true)
                    )
                    IconView(
                        source: .sfSymbol("heart.fill"),
                        style: .roundedSquare(size: AppIconSize.xl, tint: .destructiveMonochrome, hasGlassEffect: true)
                    )
                }
            }
        }
        .padding(AppSpacing.lg)
    } else {
        Text("Glass Effect requires iOS 18.0+")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .padding(AppSpacing.lg)
    }
}

// MARK: - Preview Helpers

private struct PresetSection: View {
    let title: String
    let examples: [(IconSource, IconStyle)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                ForEach(0..<examples.count, id: \.self) { index in
                    let (source, style) = examples[index]

                    VStack(spacing: AppSpacing.xs) {
                        IconView(source: source, style: style)

                        if let presetName = style.localizedPresetName {
                            Text(presetName)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }
}

private struct PlaceholderSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Placeholder")
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.lg) {
                IconView(source: nil, style: .placeholder(size: AppIconSize.xl))
                IconView(source: nil, style: .placeholder(size: AppIconSize.avatar))
                IconView(source: nil, style: .placeholder(size: AppIconSize.coin))
            }
        }
    }
}

private struct ShapeRow: View {
    let title: String
    let style: IconStyle

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            IconView(source: .sfSymbol("star.fill"), style: style)
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
    }
}

private struct TintRow: View {
    let title: String
    let style: IconStyle

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            IconView(source: .sfSymbol("paintpalette.fill"), style: style)
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
    }
}
