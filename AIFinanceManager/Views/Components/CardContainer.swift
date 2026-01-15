//
//  CardContainer.swift
//  AIFinanceManager
//
//  Reusable card container with consistent styling
//

import SwiftUI

struct CardContainer<Content: View>: View {
    let content: Content
    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }
    var body: some View {
        content
            .padding(AppSpacing.lg)
            .glassCardStyle()
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
