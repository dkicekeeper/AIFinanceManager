//
//  HealthScoreHeroCard.swift
//  Tenra
//
//  Large hero card on the Financial Health detail screen:
//  progress ring + score + grade capsule + grade-band subtitle.
//

import SwiftUI

struct HealthScoreHeroCard: View {
    let score: FinancialHealthScore
    /// True when the score is meaningful (totalIncomeWindow > 0). When false,
    /// the ring and number are replaced with an "—" placeholder.
    let isAvailable: Bool

    private var ringProgress: Double {
        isAvailable ? Double(score.score) / 100.0 : 0
    }

    private var gradeBandSubtitleKey: String {
        switch score.score {
        case 80...100: return "insights.health.subtitle.excellent"
        case 60..<80:  return "insights.health.subtitle.good"
        case 40..<60:  return "insights.health.subtitle.fair"
        default:       return "insights.health.subtitle.needsAttention"
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .stroke(AppColors.textTertiary.opacity(0.15), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(score.gradeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimation.adaptiveSpring, value: ringProgress)

                VStack(spacing: AppSpacing.xs) {
                    Text(isAvailable ? "\(score.score)" : "—")
                        .font(AppTypography.h1.bold())
                        .foregroundStyle(isAvailable ? score.gradeColor : AppColors.textTertiary)

                    Text(score.grade)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(score.gradeColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(score.gradeColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 160, height: 160)

            Text(String(localized: isAvailable
                        ? String.LocalizationValue(gradeBandSubtitleKey)
                        : "insights.health.unavailable.title"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Previews

#Preview("Good score") {
    HealthScoreHeroCard(score: FinancialHealthScore.mockGood(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Needs attention") {
    HealthScoreHeroCard(score: FinancialHealthScore.mockNeedsAttention(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Unavailable") {
    HealthScoreHeroCard(score: .unavailable(), isAvailable: false)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
