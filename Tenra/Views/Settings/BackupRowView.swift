//
//  BackupRowView.swift
//  Tenra
//
//  Single backup row with metadata and swipe actions.
//

import SwiftUI

struct BackupRowView: View {
    let metadata: BackupMetadata
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(metadata.formattedDate)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Text(metadataLine)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "settings.cloud.delete"), systemImage: "trash")
            }

            Button {
                onRestore()
            } label: {
                Label(String(localized: "settings.cloud.restore"), systemImage: "arrow.counterclockwise")
            }
            .tint(AppColors.accent)
        }
    }

    private var metadataLine: String {
        String(format: String(localized: "settings.cloud.backupMetadata"),
               metadata.accountCount, metadata.transactionCount, metadata.formattedFileSize)
    }
}
