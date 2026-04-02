//
//  CloudBackupsView.swift
//  Tenra
//
//  Backup list screen with create, restore, and delete.
//

import SwiftUI

struct CloudBackupsView: View {

    let cloudSyncViewModel: CloudSyncViewModel

    /// Counts needed for backup metadata — passed from SettingsView
    let transactionCount: Int
    let accountCount: Int
    let categoryCount: Int

    @State private var showingRestoreAlert = false
    @State private var backupToRestore: BackupMetadata?
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: BackupMetadata?

    var body: some View {
        List {
            // Create backup button
            Section {
                Button {
                    Task {
                        await cloudSyncViewModel.createBackup(
                            transactionCount: transactionCount,
                            accountCount: accountCount,
                            categoryCount: categoryCount
                        )
                    }
                } label: {
                    HStack {
                        Spacer()
                        if cloudSyncViewModel.isCreatingBackup {
                            ProgressView()
                                .padding(.trailing, AppSpacing.sm)
                        }
                        Text(String(localized: "settings.cloud.createBackup"))
                            .font(AppTypography.body)
                        Spacer()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cloudSyncViewModel.isCreatingBackup)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Backup list
            if !cloudSyncViewModel.backups.isEmpty {
                Section(header: SettingsSectionHeaderView(title: String(localized: "settings.cloud.backups"))) {
                    ForEach(cloudSyncViewModel.backups) { backup in
                        BackupRowView(
                            metadata: backup,
                            onRestore: {
                                backupToRestore = backup
                                showingRestoreAlert = true
                            },
                            onDelete: {
                                backupToDelete = backup
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.cloud.backups"))
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            // Toast messages
            VStack {
                if let successMessage = cloudSyncViewModel.successMessage {
                    MessageBanner.success(successMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                if let errorMessage = cloudSyncViewModel.errorMessage {
                    MessageBanner.error(errorMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                Spacer()
            }
        }
        .alert(
            String(localized: "alert.restore.title"),
            isPresented: $showingRestoreAlert
        ) {
            Button(String(localized: "alert.restore.confirm"), role: .destructive) {
                if let backup = backupToRestore {
                    Task { await cloudSyncViewModel.restoreBackup(backup) }
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            if let backup = backupToRestore {
                Text(String(format: String(localized: "alert.restore.message"), backup.formattedDate))
            }
        }
        .alert(
            String(localized: "settings.cloud.delete"),
            isPresented: $showingDeleteAlert
        ) {
            Button(String(localized: "settings.cloud.delete"), role: .destructive) {
                if let backup = backupToDelete {
                    cloudSyncViewModel.deleteBackup(backup)
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        }
        .task {
            cloudSyncViewModel.loadBackups()
        }
    }
}
