//
//  SkeletonView.swift
//  AIFinanceManager
//
//  Skeleton loading base component with shimmer animation (Phase 29, shimmer fixed Phase 30)

import SwiftUI

// MARK: - Shimmer Modifier

/// Overlays a left-to-right shimmer effect on any view — Liquid Glass style.
struct SkeletonShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.5), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
            }
            .clipped()
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
                ) {
                    phase = 1.5
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
    var cornerRadius: CGFloat = AppRadius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppColors.secondaryBackground)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
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
