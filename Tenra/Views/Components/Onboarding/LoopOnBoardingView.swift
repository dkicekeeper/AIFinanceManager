//
//  LoopOnBoardingView.swift
//  Tenra
//
//  Animated hero block for onboarding-style screens. Cycles through a list of
//  phases (SF Symbol + title + subtitle), bouncing the icon and emitting
//  expanding pulse rings that swell, peak, then fade before the next loop.
//
//  Two surfaces:
//  - `LoopOnboardingHero` renders just the animated icon + pulse rings for a
//    given symbol. Composable with custom layouts.
//  - `LoopOnBoardingView` is a convenience that owns the phase-cycling
//    `TimelineView` and renders the hero with title/subtitle below.
//

import SwiftUI

struct LoopOnBoardingPhase: Hashable {
    let symbol: String
    let title: String
    let subtitle: String
}

struct LoopOnBoardingConfig {
    var tint: Color = AppColors.accent
    var pulseTint: Color = AppColors.accent.opacity(0.65)
    var pulseWidth: CGFloat = 1.3
    var pulseScale: CGFloat = 12
    var iconSize: CGFloat = 100
    var iconScale: CGFloat = 1.25
    /// Seconds per phase. Each phase takes `phaseUpdateAfter * 3` seconds
    /// so the bounce + pulse keyframe track completes exactly once.
    var phaseUpdateAfter: Int = 1
}

// MARK: - Hero (icon + pulse rings only)

/// Animated icon with three staggered pulse rings, driven by `keyframeAnimator`.
/// Stateless about phase cycling — caller hands in the current symbol.
struct LoopOnboardingHero: View {
    let symbol: String
    var config: LoopOnBoardingConfig = LoopOnBoardingConfig()

    private struct Pulse {
        var scale: CGFloat = 1.0
        var opacity: CGFloat = 1.0
    }

    /// Bell curve over the ring's scale progress: ramp opacity up over the first
    /// ~35% of the expansion, hold briefly, then fade fully to 0 before the ring
    /// reaches `maxScale`. Caller multiplies by the keyframe's own opacity track.
    private static func bellOpacity(scale: CGFloat, maxScale: CGFloat) -> CGFloat {
        let denom = max(maxScale - 1, 0.001)
        let progress = min(max((scale - 1) / denom, 0), 1)
        if progress < 0.35 {
            return progress / 0.35
        } else if progress < 0.7 {
            return 1
        } else {
            return max(0, 1 - (progress - 0.7) / 0.3)
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: config.iconSize - 20))
                .foregroundStyle(config.tint.gradient)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: config.iconSize, height: config.iconSize)
                .keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    let scale = config.iconScale
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    CubicKeyframe(1, duration: 1.25)
                }

            pulseRing(delay: 0, expand: 1.5, hold: 1.5)
            pulseRing(delay: 0.5, expand: 1.5, hold: 1.0)
            pulseRing(delay: 1.0, expand: 1.5, hold: 0.5)
        }
        .frame(width: config.iconSize, height: config.iconSize)
    }

    @ViewBuilder
    private func pulseRing(delay: CGFloat, expand: CGFloat, hold: CGFloat) -> some View {
        let size = config.iconSize / 2
        let safeDelay = max(delay, 0.001)
        let safeHold = max(hold, 0.001)

        KeyframeAnimator(initialValue: Pulse(), repeating: true) { pulse in
            // Cubic interpolation can briefly overshoot below the start value;
            // clamp so we never feed a negative dimension to `frame`.
            let scale = max(pulse.scale, 0)
            let opacity = Self.bellOpacity(scale: scale, maxScale: config.pulseScale) * pulse.opacity
            Circle()
                .stroke(config.pulseTint, lineWidth: config.pulseWidth)
                .frame(width: size * scale, height: size * scale)
                .opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: safeDelay)
                // Cubic ramp gives a smoother ease-out feel than linear.
                CubicKeyframe(config.pulseScale, duration: expand)
                LinearKeyframe(config.pulseScale, duration: safeHold)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: safeDelay)
                LinearKeyframe(1, duration: expand)
                LinearKeyframe(0, duration: safeHold)
            }
        }
    }
}

// MARK: - Phase Text Transition

/// Insertion: slides up from below + un-blurs + fades in.
/// Removal: keeps sliding up off-screen + blurs + fades out.
/// Used on the synced title/subtitle block beneath/around the hero.
struct LoopOnboardingTextTransition: Transition {
    var slideDistance: CGFloat = 24
    var blurRadius: CGFloat = 10

    func body(content: Content, phase: TransitionPhase) -> some View {
        let yOffset: CGFloat = {
            switch phase {
            case .willAppear: return slideDistance      // start below identity
            case .identity: return 0
            case .didDisappear: return -slideDistance   // exit upward
            }
        }()

        return content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : blurRadius)
            .offset(y: yOffset)
    }
}

// MARK: - Convenience: hero + caption stacked

/// Cycles through phases and renders the hero with title/subtitle stacked below.
/// Most onboarding screens compose `LoopOnboardingHero` directly instead, because
/// they want custom layout (e.g. text near the CTA, hero floating in the middle).
struct LoopOnBoardingView: View {
    let phases: [LoopOnBoardingPhase]
    var config: LoopOnBoardingConfig = LoopOnBoardingConfig()
    var onPhaseChange: ((Int) -> Void)? = nil

    @State private var startDate: Date = .now

    var body: some View {
        if phases.isEmpty {
            EmptyView()
        } else {
            let timelineDuration = CGFloat(config.phaseUpdateAfter) * 3.0

            TimelineView(.periodic(from: startDate, by: timelineDuration)) { ctx in
                let diff = Int(startDate.distance(to: ctx.date)) / (config.phaseUpdateAfter * 3)
                let index = diff % phases.count
                let phase = phases[index]

                VStack(spacing: AppSpacing.xxl) {
                    LoopOnboardingHero(symbol: phase.symbol, config: config)

                    VStack(spacing: AppSpacing.sm) {
                        Text(phase.title)
                            .font(AppTypography.h3)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(phase.subtitle)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    .id(index)
                    .transition(LoopOnboardingTextTransition())
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: index)
                .onChange(of: index) { _, newValue in
                    onPhaseChange?(newValue)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Loop Hero — globe") {
    LoopOnboardingHero(symbol: "globe")
        .padding(40)
}

#Preview("Loop OnBoarding — cycle") {
    LoopOnBoardingView(phases: [
        LoopOnBoardingPhase(symbol: "chart.pie.fill", title: "Phase 1", subtitle: "First phase subtitle"),
        LoopOnBoardingPhase(symbol: "mic.fill", title: "Phase 2", subtitle: "Second phase subtitle"),
        LoopOnBoardingPhase(symbol: "lock.shield.fill", title: "Phase 3", subtitle: "Third phase subtitle"),
    ])
    .padding()
}
