//
//  CardContainer.swift
//  AIFinanceManager
//
//  Reusable card container with consistent styling
//

import SwiftUI

struct CardContainer<Content: View>: View {
    let content: Content
//    let cornerRadius: CGFloat
//    let padding: CGFloat
    
    init(
//        cornerRadius: CGFloat = AppRadius.lg,
//        padding: CGFloat = AppSpacing.xs,
        @ViewBuilder content: () -> Content
    ) {
//        self.cornerRadius = cornerRadius
//        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(AppSpacing.md)
            .glassEffect(in: .rect(cornerRadius: AppRadius.md))
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
