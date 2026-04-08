//
//  SiriGlowView.swift
//  Tenra
//
//  Apple Intelligence–style edge glow using MeshGradient.
//  Blobs orbit the full perimeter; voice fills the entire screen.
//

import SwiftUI

struct SiriGlowView: View {

    var amplitudeRef: AudioLevelRef

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let a = Double(amplitudeRef.value)
            meshGlow(t: t, amp: a)
        }
    }

    @ViewBuilder
    private func meshGlow(t: Double, amp: Double) -> some View {
        let points = buildPoints(t: t, amp: amp)
        let colors = buildColors(t: t, amp: amp)

        MeshGradient(width: 5, height: 5, points: points, colors: colors)
            .blur(radius: 30 + CGFloat(amp) * 20)
            .opacity(0.75 + amp * 0.25)
            .allowsHitTesting(false)
    }

    // MARK: - Colors: rotate hues around the perimeter

    private func buildColors(t: Double, amp: Double) -> [Color] {
        // 12 vivid hues cycling. Edge points sample from this rotating palette.
        let hues: [Color] = [
            .init(red: 0.55, green: 0.10, blue: 1.00),  // purple
            .init(red: 0.00, green: 0.75, blue: 1.00),  // cyan
            .init(red: 0.10, green: 0.85, blue: 0.65),  // emerald
            .init(red: 1.00, green: 0.60, blue: 0.10),  // amber
            .init(red: 1.00, green: 0.30, blue: 0.55),  // hot pink
            .init(red: 0.90, green: 0.20, blue: 0.80),  // magenta
            .init(red: 0.25, green: 0.45, blue: 1.00),  // cobalt
            .init(red: 1.00, green: 0.45, blue: 0.70),  // coral
            .init(red: 0.65, green: 0.25, blue: 1.00),  // violet
            .init(red: 0.15, green: 0.60, blue: 1.00),  // azure
            .init(red: 0.55, green: 0.10, blue: 1.00),  // purple (wrap)
            .init(red: 0.00, green: 0.75, blue: 1.00),  // cyan (wrap)
        ]

        // Slow rotation through palette
        let shift = t * 0.06
        func hue(_ i: Double) -> Color {
            let idx = (i + shift).truncatingRemainder(dividingBy: Double(hues.count - 1))
            let i0 = Int(idx) % (hues.count - 1)
            return hues[i0]
        }

        // Side color opacity: driven by amplitude
        let sideAlpha = 0.3 + amp * 0.5

        // 5×5 grid color layout:
        // Row 0: top edge (5 colors)
        // Row 1: near-top (side colors + transparent center)
        // Row 2: middle (side colors + transparent center)
        // Row 3: near-bottom (side colors + transparent center)
        // Row 4: bottom edge (5 colors)
        return [
            // Row 0 — top edge: all vivid
            hue(0), hue(1), hue(2), hue(3), hue(4),
            // Row 1 — left vivid, center clear, right vivid
            hue(9).opacity(sideAlpha), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(5).opacity(sideAlpha),
            // Row 2 — middle: sides only
            hue(8).opacity(sideAlpha), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(6).opacity(sideAlpha),
            // Row 3 — left vivid, center clear, right vivid
            hue(7).opacity(sideAlpha), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(7).opacity(sideAlpha),
            // Row 4 — bottom edge: all vivid
            hue(5), hue(6), hue(7), hue(8), hue(9),
        ]
    }

    // MARK: - Points: orbit + voice distortion

    private func buildPoints(t: Double, amp: Double) -> [SIMD2<Float>] {
        // Amplitude: quadratic for explosive feel
        let a2 = amp * amp
        let a3 = a2 * amp

        // Interior rows/cols: hug edges in silence, push to center with voice
        // silence: 0.06 from edge. max voice: up to 0.50 (fills entire screen)
        let push = Float(a2 * 0.30)
        // Rounder blobs: more evenly spaced grid, not squeezed to edges
        let inner1 = 0.15 + push      // silence: 0.15, loud: 0.45
        let inner2 = 0.85 - push      // silence: 0.85, loud: 0.55

        let rowY: [Float] = [0.0, inner1, 0.5, inner2, 1.0]
        let colX: [Float] = [0.0, inner1, 0.5, inner2, 1.0]

        var pts = [SIMD2<Float>](repeating: .zero, count: 25)

        for row in 0..<5 {
            for col in 0..<5 {
                let idx = row * 5 + col
                let isCorner = (row == 0 || row == 4) && (col == 0 || col == 4)
                let isEdge = row == 0 || row == 4 || col == 0 || col == 4
                let isInner = !isEdge

                var x = Double(colX[col])
                var y = Double(rowY[row])

                if isCorner {
                    // Corners pinned
                    pts[idx] = SIMD2<Float>(Float(x), Float(y))
                    continue
                }

                let seed = Double(idx) * 1.7

                if isEdge {
                    // Edge points: slow orbit in silence, dramatic with voice
                    let s1 = 0.4 + seed.truncatingRemainder(dividingBy: 0.5)
                    let s2 = 0.35 + (seed * 1.3).truncatingRemainder(dividingBy: 0.45)

                    let silenceWobble = 0.03
                    let voiceWobble = a2 * 0.25
                    let range = silenceWobble + voiceWobble

                    x += sin(t * s1 + seed) * range
                    y += cos(t * s2 + seed * 1.4) * range

                    // High-freq shake on loud sounds
                    let shake = a3 * 0.05
                    x += sin(t * 9.0 + seed * 2.1) * shake
                    y += cos(t * 8.0 + seed * 3.3) * shake

                    // Clamp: near own edge, allowed to push further with voice
                    let edgeRange = 0.10 + amp * 0.20
                    if col == 0 { x = max(-0.03, min(x, Double(inner1) + 0.02)) }
                    if col == 4 { x = min(1.03, max(x, Double(inner2) - 0.02)) }
                    if row == 0 { y = max(-0.03, min(y, Double(inner1) + 0.02)) }
                    if row == 4 { y = min(1.03, max(y, Double(inner2) - 0.02)) }
                    // Middle edge points can move along their edge freely
                    if col > 0 && col < 4 && (row == 0 || row == 4) {
                        x = max(0.0, min(1.0, x))
                    }
                    if row > 0 && row < 4 && (col == 0 || col == 4) {
                        y = max(0.0, min(1.0, y))
                    }
                    _ = edgeRange // suppress warning

                } else {
                    // Interior: voice pushes them around creating distortion
                    let drift = 0.01 + a2 * 0.12
                    x += sin(t * 0.4 + seed) * drift
                    y += cos(t * 0.35 + seed * 1.5) * drift
                }

                pts[idx] = SIMD2<Float>(Float(x), Float(y))
            }
        }

        return pts
    }
}

#Preview("Siri Glow") {
    let ref = AudioLevelRef()
    ref.value = 0.4
    return ZStack {
        Color.white
        Text("Siri Glow").font(.title2)
    }
    .overlay { SiriGlowView(amplitudeRef: ref).ignoresSafeArea() }
}
