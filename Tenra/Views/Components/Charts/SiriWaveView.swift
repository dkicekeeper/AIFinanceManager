//
//  SiriWaveView.swift
//  Tenra
//
//  Voice recording glow overlay wrapper.
//  Uses SiriGlowView (MeshGradient-based) for the visual effect.
//

import SwiftUI

/// Apple Intelligence–style edge glow overlay.
/// Designed as a full-screen `.overlay()` — passes through all touches.
/// Fades in on appear for smooth transition.
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

// MARK: - Preview

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
