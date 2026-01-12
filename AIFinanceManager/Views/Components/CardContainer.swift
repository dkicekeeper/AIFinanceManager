//
//  CardContainer.swift
//  AIFinanceManager
//
//  Reusable card container with consistent styling
//

import SwiftUI

struct CardContainer<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let padding: CGFloat
    
    init(
        cornerRadius: CGFloat = AppRadius.lg,
        padding: CGFloat = AppSpacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadowStyle(AppShadow.md)
    }
}

#Preview("Card Container") {
    CardContainer {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Card Title")
                .font(AppTypography.h3)
            Text("Card content goes here")
                .font(AppTypography.body)
        }
    }
    .padding()
}
