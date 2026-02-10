//
//  SuccessMessageView.swift
//  AIFinanceManager
//
//  Created on 2026-02-10
//

import SwiftUI

struct SuccessMessageView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AppIconSize.md))
            Text(message)
                .font(AppTypography.body)
        }
        .padding(AppSpacing.md)
        .cornerRadius(AppRadius.pill)
        .glassEffect(.regular
            .tint(.green.opacity(0.5))
            .interactive())
    }
}
