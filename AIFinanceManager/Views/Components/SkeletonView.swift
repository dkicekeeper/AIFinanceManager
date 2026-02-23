//
//  SkeletonView.swift
//  AIFinanceManager
//
//  Skeleton loading base component with shimmer animation (Phase 29)

import SwiftUI

// MARK: - Shimmer Modifier

/// Overlays a left-to-right shimmer blick on any view — Liquid Glass style.
struct SkeletonShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.3), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
                .blendMode(.plusLighter)
            }
            .clipped()
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
                ) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    /// Adds a left-to-right shimmer animation (Liquid Glass style).
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmerModifier())
    }
}

// MARK: - SkeletonView

/// Base skeleton block. Use width: nil to fill available horizontal space.
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
            .skeletonShimmer()
    }
}

// MARK: - Preview

#Preview("Shimmer") {
    VStack(spacing: 16) {
        SkeletonView(height: 16)
        SkeletonView(width: 200, height: 16)
        SkeletonView(height: 80, cornerRadius: 20)
        SkeletonView(width: 44, height: 44, cornerRadius: 22)
    }
    .padding()
}
