//
//  SiriWaveView.swift
//  Tenra
//
//  Voice recording glow overlay.
//  SiriWaveRecordingView wraps SiriGlowView (MeshGradient-based).
//  Legacy SiriWaveView kept for API compatibility.
//

import SwiftUI

// MARK: - SiriWaveRecordingView

/// Apple Intelligence–style edge glow overlay.
/// Uses `SiriGlowView` (MeshGradient) for smooth, GPU-accelerated gradients.
/// Designed as a full-screen `.overlay()` — passes through all touches.
struct SiriWaveRecordingView: View {

    var amplitudeRef: AudioLevelRef

    @State private var isVisible = false

    var body: some View {
        SiriGlowView(amplitudeRef: amplitudeRef)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(AppAnimation.gentleSpring) {
                    isVisible = true
                }
            }
    }
}

// MARK: - SiriWaveView (Legacy API)

/// Legacy wave view. Kept for API compatibility (used in previews).
struct SiriWaveView: View {

    let amplitude: Double
    var color: Color = AppColors.accent
    var frequency: Double = 4
    var animationSpeed: Double = 1.5

    init(
        amplitude: Double = 30,
        frequency: Double = 4,
        color: Color = AppColors.accent,
        animationSpeed: Double = 1.5
    ) {
        self.amplitude = amplitude
        self.frequency = frequency
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        let ref = AudioLevelRef()
        let _ = { ref.value = Float(amplitude / 60.0).clamped(to: 0.1...1.0) }()
        SiriGlowView(amplitudeRef: ref)
    }
}

// MARK: - Float helper

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

// MARK: - Previews

#Preview("Edge Glow") {
    let ref = AudioLevelRef()
    ref.value = 0.5
    return ZStack {
        Color.white
        VStack(spacing: 20) {
            Text("Edge Glow Recording")
                .font(AppTypography.bodyEmphasis)
            Text("Amplitude: 0.5")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
    .overlay {
        SiriWaveRecordingView(amplitudeRef: ref)
            .ignoresSafeArea()
    }
}
