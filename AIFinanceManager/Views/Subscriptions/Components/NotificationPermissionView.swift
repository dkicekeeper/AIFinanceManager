//
//  NotificationPermissionView.swift
//  AIFinanceManager
//
//  Created on 2026-02-14
//  Purpose: Request notification permissions for subscription reminders
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    let onAllow: () async -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .padding(.bottom, AppSpacing.md)

            // Title
            Text("Включить напоминания?")
                .font(AppTypography.h2)
                .multilineTextAlignment(.center)

            // Description
            Text("Получайте уведомления о предстоящих списаниях по подпискам, чтобы не пропустить важные платежи")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            Spacer()

            // Buttons
            VStack(spacing: AppSpacing.md) {
                Button {
                    HapticManager.light()
                    Task {
                        await onAllow()
                        dismiss()
                    }
                } label: {
                    Text("Разрешить уведомления")
                        .font(AppTypography.body)
                        .bold()
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(.blue)
                        .clipShape(.rect(cornerRadius: AppRadius.md))
                }

                Button {
                    HapticManager.light()
                    onSkip()
                    dismiss()
                } label: {
                    Text("Не сейчас")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
        .padding(.top, AppSpacing.xl)
    }
}

#Preview {
    NotificationPermissionView(
        onAllow: { },
        onSkip: { }
    )
}
