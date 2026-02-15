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
        Group {
            if #available(iOS 26, *) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: AppIconSize.md))
                    Text(message)
                        .font(AppTypography.body)
                }
                .padding(AppSpacing.md)
                .clipShape(.rect(cornerRadius: AppRadius.pill))
                .glassEffect(.regular
                    .tint(.green.opacity(0.15))
                    .interactive())
            } else {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: AppIconSize.md))
                    Text(message)
                        .font(AppTypography.body)
                }
                .padding(AppSpacing.md)
                .background(
                    Color.green.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: AppRadius.pill)
                )
            }
        }
    }
}
