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
        Group {
            if #available(iOS 26, *) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: AppIconSize.md))
                    Text(message)
                        .font(AppTypography.body)
                }
                .padding(AppSpacing.md)
                .clipShape(.rect(cornerRadius: AppRadius.pill))
                .glassEffect(.regular
                    .tint(.red.opacity(0.15))
                    .interactive())
            } else {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: AppIconSize.md))
                    Text(message)
                        .font(AppTypography.body)
                }
                .padding(AppSpacing.md)
                .background(
                    Color.red.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: AppRadius.pill)
                )
            }
        }
    }
}
