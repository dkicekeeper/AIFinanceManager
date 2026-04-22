//
//  CloudSyncViewModel.swift
//  Tenra
//
//  UI state for local backups. iCloud sync was removed 2026-04-22 —
//  CloudKit's HistoryExpired events were triggering data loss on restart.
//  The class name is kept to avoid renaming across call sites; despite the
//  name, it now manages only on-device backups in Documents/Backups.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class CloudSyncViewModel {

    private nonisolated static let logger = Logger(subsystem: "Tenra", category: "CloudSyncViewModel")

    // MARK: - Observable State

    var backups: [BackupMetadata] = []
    var isCreatingBackup = false
    var isRestoringBackup = false
    var storageUsed: Int64 = 0
    var successMessage: String?
    var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored private let backupService: CloudBackupService
    @ObservationIgnored private let coreDataStack: CoreDataStack

    /// Set by AppCoordinator after init — used for full re-initialization after restore
    @ObservationIgnored weak var appCoordinator: AppCoordinator?

    // MARK: - Init

    init(
        backupService: CloudBackupService,
        coreDataStack: CoreDataStack = .shared
    ) {
        self.backupService = backupService
        self.coreDataStack = coreDataStack
    }

    // MARK: - Backups

    func loadBackups() {
        backups = backupService.listBackups()
        storageUsed = backupService.estimateStorageUsed()
    }

    func createBackup(transactionCount: Int, accountCount: Int, categoryCount: Int) async {
        isCreatingBackup = true
        do {
            let metadata = try await backupService.createBackup(
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount
            )
            backups.insert(metadata, at: 0)
            storageUsed = backupService.estimateStorageUsed()
            await showSuccess(String(localized: "settings.cloud.backupCreated"))
        } catch {
            await showError(error.localizedDescription)
        }
        isCreatingBackup = false
    }

    func restoreBackup(_ metadata: BackupMetadata) async {
        isRestoringBackup = true

        do {
            try await backupService.restoreBackup(metadata)
            // swapStore posts storeDidResetNotification (FRC rebuilds) but in-memory
            // stores (TransactionStore, BalanceCoordinator, etc.) need a full reload.
            if let coordinator = appCoordinator {
                try? await coordinator.transactionStore.loadData()
                coordinator.syncTransactionStoreToViewModels(batchMode: true)
                await coordinator.balanceCoordinator.registerAccounts(coordinator.transactionStore.accounts)
            }
            await showSuccess(String(localized: "settings.cloud.restoreSuccess"))
        } catch {
            await showError(error.localizedDescription)
        }

        isRestoringBackup = false
    }

    func deleteBackup(_ metadata: BackupMetadata) {
        do {
            try backupService.deleteBackup(metadata)
            backups.removeAll { $0.id == metadata.id }
            storageUsed = backupService.estimateStorageUsed()
        } catch {
            Task { await showError(error.localizedDescription) }
        }
    }

    // MARK: - Messages

    private func showSuccess(_ message: String) async {
        successMessage = message
        try? await Task.sleep(for: .seconds(3))
        successMessage = nil
    }

    private func showError(_ message: String) async {
        errorMessage = message
        try? await Task.sleep(for: .seconds(5))
        errorMessage = nil
    }
}
