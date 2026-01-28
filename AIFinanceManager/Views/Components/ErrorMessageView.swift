//
//  ErrorMessageView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AppIconSize.md))
            Text(message)
                .font(AppTypography.body)
        }
        .padding(AppSpacing.md)
        .background(Color.red.opacity(0.1))
        .foregroundColor(.red)
        .cornerRadius(AppRadius.sm)
    }
}
