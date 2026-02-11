//
//  SiriWaveView.swift
//  AIFinanceManager
//
//  Created on 2026-01-19
//

import SwiftUI

/// Siri-like wave animation for recording indicator
/// Uses Canvas for smooth, performant animation
struct SiriWaveView: View {

    // MARK: - Properties

    /// Amplitude of the wave (height)
    let amplitude: Double

    /// Frequency of the wave (number of peaks)
    let frequency: Double

    /// Color of the wave
    let color: Color

    /// Animation speed (duration for one full cycle in seconds)
    let animationSpeed: Double

    // MARK: - Initialization

    init(
        amplitude: Double = 30,
        frequency: Double = 4,
        color: Color = .blue,
        animationSpeed: Double = 1.5
    ) {
        self.amplitude = amplitude
        self.frequency = frequency
        self.color = color
        self.animationSpeed = animationSpeed
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.016)) { timeline in
            Canvas { context, size in
                // Calculate phase based on current time
                let elapsed = timeline.date.timeIntervalSince1970
                let currentPhase = (elapsed * 2 * .pi / animationSpeed).truncatingRemainder(dividingBy: 2 * .pi)
                
                let path = createWavePath(size: size, phase: currentPhase)
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Private Methods

    /// Create wave path for Canvas
    /// - Parameters:
    ///   - size: Canvas size
    ///   - phase: Current animation phase
    /// - Returns: Path representing the wave
    private func createWavePath(size: CGSize, phase: Double) -> Path {
        var path = Path()

        let width = size.width
        let height = size.height
        let midY = height / 2

        path.move(to: CGPoint(x: 0, y: midY))

        // Generate smooth wave using sine function
        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / width
            let sine = sin((relativeX * frequency * 2 * .pi) + phase)
            let y = midY + (sine * amplitude)

            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

// MARK: - Multi-Wave View

/// Recording indicator with multiple overlapping waves (like Siri)
struct SiriWaveRecordingView: View {

    // MARK: - Animation State

    @State private var isAnimating = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background wave (slower, lighter)
            SiriWaveView(
                amplitude: 20,
                frequency: 3,
                color: .blue.opacity(0.3),
                animationSpeed: 2.0
            )
            .frame(height: 80)

            // Middle wave (medium speed)
            SiriWaveView(
                amplitude: 25,
                frequency: 4,
                color: .blue.opacity(0.6),
                animationSpeed: 1.5
            )
            .frame(height: 80)

            // Foreground wave (faster, more opaque)
            SiriWaveView(
                amplitude: 30,
                frequency: 5,
                color: .blue,
                animationSpeed: 1.2
            )
            .frame(height: 80)

            // Recording text
            VStack {
                Spacer()
                Text(String(localized: "voice.recording"))
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(.blue)
                    .opacity(isAnimating ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
            }
        }
        .frame(height: 100)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview("Single Wave") {
    VStack(spacing: 40) {
        Text("Single Wave")
            .font(.headline)

        SiriWaveView(
            amplitude: 30,
            frequency: 4,
            color: .blue
        )
        .frame(height: 80)
        .padding()
    }
}

#Preview("Recording Indicator") {
    VStack(spacing: 40) {
        Text("Siri-like Recording")
            .font(.headline)

        SiriWaveRecordingView()
            .padding()
    }
}
