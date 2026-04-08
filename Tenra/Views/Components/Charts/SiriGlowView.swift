//
//  SiriGlowView.swift
//  Tenra
//
//  Apple Intelligence–style edge glow using MeshGradient.
//  5×7 grid: more vertical rows for even side color density on tall screens.
//

import SwiftUI

struct SiriGlowView: View {

    var amplitudeRef: AudioLevelRef

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let a = Double(amplitudeRef.value)
                let aspect = geo.size.width / max(geo.size.height, 1)
                meshGlow(t: t, amp: a, aspect: aspect)
            }
        }
    }

    @ViewBuilder
    private func meshGlow(t: Double, amp: Double, aspect: Double) -> some View {
        let points = buildPoints(t: t, amp: amp, aspect: aspect)
        let colors = buildColors(t: t, amp: amp)

        // width=5 cols, height=7 rows → 35 points
        MeshGradient(width: 5, height: 7, points: points, colors: colors)
            .blur(radius: 30 + CGFloat(amp) * 20)
            .opacity(0.75 + amp * 0.25)
            .allowsHitTesting(false)
    }

    // MARK: - Colors: 5×7 = 35 colors

    private func buildColors(t: Double, amp: Double) -> [Color] {
        func hue(phase: Double) -> Color {
            let slow = t * 0.18 + phase
            let r = 0.55 + 0.45 * sin(slow)
            let g = 0.35 + 0.35 * sin(slow * 1.3 + 2.1)
            let b = 0.55 + 0.45 * sin(slow * 0.7 + 4.2)
            return Color(red: r, green: g, blue: b)
        }

        let sa = 0.4 + amp * 0.5 // side alpha

        // 7 rows × 5 cols. Left/right cols vivid, center 3 cols transparent.
        return [
            // Row 0 — top edge
            hue(phase: 0.0), hue(phase: 1.5), hue(phase: 3.0), hue(phase: 4.5), hue(phase: 6.0),
            // Row 1 — near-top
            hue(phase: 13.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 7.0).opacity(sa),
            // Row 2 — upper-mid
            hue(phase: 12.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 8.0).opacity(sa),
            // Row 3 — center
            hue(phase: 11.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 9.0).opacity(sa),
            // Row 4 — lower-mid
            hue(phase: 10.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 10.0).opacity(sa),
            // Row 5 — near-bottom
            hue(phase: 9.0).opacity(sa), .white.opacity(0), .white.opacity(0), .white.opacity(0), hue(phase: 11.0).opacity(sa),
            // Row 6 — bottom edge
            hue(phase: 6.5), hue(phase: 8.0), hue(phase: 9.5), hue(phase: 11.0), hue(phase: 12.5),
        ]
    }

    // MARK: - Points: 5×7 grid, aspect-corrected

    private func buildPoints(t: Double, amp: Double, aspect: Double) -> [SIMD2<Float>] {
        let a2 = amp * amp
        let glowFraction = 0.15 + a2 * 0.30

        let insetX = Float(glowFraction)
        let insetY = Float(glowFraction * min(aspect, 1.0))

        // 5 columns
        let colX: [Float] = [0.0, insetX, 0.5, 1.0 - insetX, 1.0]

        // 7 rows: evenly distributed for uniform side color density
        // Rows 0,6 = outer edges. Rows 1-5 = inner, evenly spaced between insetY and 1-insetY.
        let innerSpan = 1.0 - 2.0 * Double(insetY)
        var rowY: [Float] = [0.0]
        rowY.append(insetY)
        for i in 1...3 {
            rowY.append(Float(Double(insetY) + innerSpan * Double(i) / 4.0))
        }
        rowY.append(1.0 - insetY)
        rowY.append(1.0)
        // rowY now has 7 entries: [0, insetY, 25%, 50%, 75%, 1-insetY, 1]

        let rows = 7
        let cols = 5
        var pts = [SIMD2<Float>](repeating: .zero, count: rows * cols)

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let isOuterRow = (row == 0 || row == rows - 1)
                let isOuterCol = (col == 0 || col == cols - 1)

                let x = Double(colX[col])
                let y = Double(rowY[row])

                if isOuterRow || isOuterCol {
                    pts[idx] = SIMD2<Float>(Float(x), Float(y))
                } else {
                    // Inner points: wobble + voice
                    let seed = Double(idx) * 1.7
                    let s1 = 0.3 + seed.truncatingRemainder(dividingBy: 0.4)
                    let s2 = 0.25 + (seed * 1.3).truncatingRemainder(dividingBy: 0.35)

                    let range = 0.02 + a2 * 0.15
                    var px = x + sin(t * s1 + seed) * range
                    var py = y + cos(t * s2 + seed * 1.4) * range

                    let shake = a2 * amp * 0.04
                    px += sin(t * 7.0 + seed * 2.1) * shake
                    py += cos(t * 6.0 + seed * 3.3) * shake

                    pts[idx] = SIMD2<Float>(Float(px), Float(py))
                }
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
