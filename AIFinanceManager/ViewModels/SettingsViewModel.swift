//
//  SettingsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import SwiftUI
import Combine

/// ViewModel for Settings screen
/// Coordinates all settings operations through specialized services
/// Follows Single Responsibility Principle with Protocol-Oriented Design
@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published State

    @Published var settings: AppSettings
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - Wallpaper State

    @Published var currentWallpaper: UIImage?
    @Published var wallpaperHistory: [WallpaperHistoryItem] = []

    // MARK: - Export/Import Progress

    @Published var exportProgress: Double = 0
    @Published var isExporting: Bool = false

    // MARK: - Import Flow State

    @Published var importFlowCoordinator: ImportFlowCoordinator?

    // MARK: - Dependencies (Protocol-oriented for testability)

    private let storageService: SettingsStorageServiceProtocol
    private let wallpaperService: WallpaperManagementServiceProtocol
    private let resetCoordinator: DataResetCoordinatorProtocol
    private let validationService: SettingsValidationServiceProtocol
    private let exportCoordinator: ExportCoordinatorProtocol
    private let importCoordinator: CSVImportCoordinatorProtocol?

    // MARK: - ViewModel References (weak to prevent retain cycles)

    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var accountsViewModel: AccountsViewModel?

    // MARK: - Initialization

    init(
        storageService: SettingsStorageServiceProtocol,
        wallpaperService: WallpaperManagementServiceProtocol,
        resetCoordinator: DataResetCoordinatorProtocol,
        validationService: SettingsValidationServiceProtocol,
        exportCoordinator: ExportCoordinatorProtocol,
        importCoordinator: CSVImportCoordinatorProtocol? = nil,
        transactionsViewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        initialSettings: AppSettings? = nil
    ) {
        self.storageService = storageService
        self.wallpaperService = wallpaperService
        self.resetCoordinator = resetCoordinator
        self.validationService = validationService
        self.exportCoordinator = exportCoordinator
        self.importCoordinator = importCoordinator
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.settings = initialSettings ?? AppSettings.makeDefault()
    }

    // MARK: - Lifecycle

    /// Load settings and wallpaper on initialization
    func loadInitialData() async {
        await loadSettings()
        await loadCurrentWallpaper()
        await loadWallpaperHistory()
    }

    // MARK: - Settings Operations

    /// Update base currency
    func updateBaseCurrency(_ currency: String) async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Updating base currency to: \(currency)")
        #endif

        do {
            // Validate currency
            try validationService.validateCurrency(currency)

            // Update settings
            settings.baseCurrency = currency

            // Save to storage
            try await storageService.saveSettings(settings)

            await showSuccess(String(localized: "success.settings.currencyUpdated", defaultValue: "Currency updated successfully"))

            #if DEBUG
            print("✅ [SettingsViewModel] Currency updated")
            #endif
        } catch {
            await showError(error.localizedDescription)
        }
    }

    /// Select new wallpaper
    func selectWallpaper(_ image: UIImage) async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Selecting new wallpaper")
        #endif

        await setLoading(true)

        do {
            // Remove old wallpaper if exists
            if let oldFileName = settings.wallpaperImageName {
                try? await wallpaperService.removeWallpaper(named: oldFileName)
            }

            // Save new wallpaper
            let fileName = try await wallpaperService.saveWallpaper(image)

            // Update settings
            settings.wallpaperImageName = fileName

            // Save to storage
            try await storageService.saveSettings(settings)

            // Update current wallpaper
            currentWallpaper = image

            // Reload history
            await loadWallpaperHistory()

            await showSuccess(String(localized: "success.settings.wallpaperUpdated", defaultValue: "Wallpaper updated successfully"))

            #if DEBUG
            print("✅ [SettingsViewModel] Wallpaper selected")
            #endif
        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    /// Remove current wallpaper
    func removeWallpaper() async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Removing wallpaper")
        #endif

        guard let fileName = settings.wallpaperImageName else {
            return
        }

        await setLoading(true)

        do {
            // Remove file
            try await wallpaperService.removeWallpaper(named: fileName)

            // Update settings
            settings.wallpaperImageName = nil

            // Save to storage
            try await storageService.saveSettings(settings)

            // Clear current wallpaper
            currentWallpaper = nil

            await showSuccess(String(localized: "success.settings.wallpaperRemoved", defaultValue: "Wallpaper removed successfully"))

            #if DEBUG
            print("✅ [SettingsViewModel] Wallpaper removed")
            #endif
        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    // MARK: - Export/Import Operations

    /// Export all data to CSV
    func exportAllData() async -> URL? {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Exporting all data")
        #endif

        isExporting = true
        exportProgress = 0

        do {
            let fileURL = try await exportCoordinator.exportAllData()

            exportProgress = 1.0

            await showSuccess(String(localized: "success.export.completed", defaultValue: "Data exported successfully"))

            #if DEBUG
            print("✅ [SettingsViewModel] Export completed")
            #endif

            isExporting = false
            return fileURL
        } catch {
            await showError(error.localizedDescription)
            isExporting = false
            return nil
        }
    }

    /// Start CSV import flow
    /// - Parameter url: URL of CSV file to import
    func startImportFlow(from url: URL) async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Starting import flow")
        #endif

        guard let transactionsViewModel = transactionsViewModel,
              let categoriesViewModel = categoriesViewModel else {
            await showError(String(localized: "error.import.viewModelsNotAvailable", defaultValue: "Required view models not available"))
            return
        }

        // Create flow coordinator (it will create CSVImportCoordinator lazily)
        let flowCoordinator = ImportFlowCoordinator(
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel
        )

        importFlowCoordinator = flowCoordinator

        // Start import
        await flowCoordinator.startImport(from: url)
    }

    /// Cancel import flow
    func cancelImportFlow() {
        importFlowCoordinator?.cancel()
        importFlowCoordinator = nil
    }

    // MARK: - Dangerous Operations

    /// Reset all application data
    func resetAllData() async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Resetting all data")
        #endif

        await setLoading(true)

        do {
            try await resetCoordinator.resetAllData()

            await showSuccess(String(localized: "success.reset.completed", defaultValue: "All data has been reset"))

            #if DEBUG
            print("✅ [SettingsViewModel] Data reset completed")
            #endif
        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    /// Recalculate all account balances
    func recalculateBalances() async {
        #if DEBUG
        print("⚙️ [SettingsViewModel] Recalculating balances")
        #endif

        await setLoading(true)

        do {
            try await resetCoordinator.recalculateAllBalances()

            await showSuccess(String(localized: "success.recalculation.completed", defaultValue: "Balances recalculated successfully"))

            #if DEBUG
            print("✅ [SettingsViewModel] Recalculation completed")
            #endif
        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    // MARK: - Private Helpers

    private func loadSettings() async {
        do {
            settings = try await storageService.loadSettings()

            #if DEBUG
            print("✅ [SettingsViewModel] Settings loaded")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SettingsViewModel] Failed to load settings: \(error)")
            #endif

            // Use default on error
            settings = AppSettings.makeDefault()
        }
    }

    private func loadCurrentWallpaper() async {
        guard let fileName = settings.wallpaperImageName else {
            currentWallpaper = nil
            return
        }

        do {
            currentWallpaper = try await wallpaperService.loadWallpaper(named: fileName)

            #if DEBUG
            print("✅ [SettingsViewModel] Wallpaper loaded")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [SettingsViewModel] Failed to load wallpaper: \(error)")
            #endif

            // Clear invalid wallpaper reference
            settings.wallpaperImageName = nil
            try? await storageService.saveSettings(settings)
            currentWallpaper = nil
        }
    }

    private func loadWallpaperHistory() async {
        wallpaperHistory = await wallpaperService.getWallpaperHistory()
    }

    private func setLoading(_ loading: Bool) async {
        isLoading = loading
    }

    private func showError(_ message: String) async {
        errorMessage = message
        successMessage = nil

        #if DEBUG
        print("❌ [SettingsViewModel] Error: \(message)")
        #endif

        // Auto-clear after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if self.errorMessage == message {
                    self.errorMessage = nil
                }
            }
        }
    }

    private func showSuccess(_ message: String) async {
        successMessage = message
        errorMessage = nil

        #if DEBUG
        print("✅ [SettingsViewModel] Success: \(message)")
        #endif

        // Auto-clear after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self.successMessage == message {
                    self.successMessage = nil
                }
            }
        }
    }
}
