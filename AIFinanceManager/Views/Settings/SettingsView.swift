//
//  SettingsView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Refactored: 2026-02-04 Phase 2 (CSV Migration)
//  Refactored: 2026-02-04 Phase 3 (UI Decomposition)
//

import SwiftUI
import PhotosUI

/// Main Settings screen with modular component-based architecture
/// Follows Single Responsibility Principle with Props pattern
struct SettingsView: View {
    // MARK: - Dependencies

    @ObservedObject var settingsViewModel: SettingsViewModel

    // Legacy ViewModels (navigation only)
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
    @ObservedObject var depositsViewModel: DepositsViewModel

    // MARK: - State

    @State private var showingResetConfirmation = false
    @State private var showingRecalculateBalancesConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil

    // MARK: - Body

    var body: some View {
        ImportFlowSheetsContainer(
            flowCoordinator: settingsViewModel.importFlowCoordinator,
            onCancel: { settingsViewModel.cancelImportFlow() }
        ) {
            settingsList
        }
    }

    // MARK: - Main List

    private var settingsList: some View {
        List {
            generalSection
            dataManagementSection
            exportImportSection
            dangerZoneSection
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .alert(
            String(localized: "alert.recalculateBalances.title"),
            isPresented: $showingRecalculateBalancesConfirmation
        ) {
            Button(String(localized: "alert.recalculateBalances.confirm"), role: .destructive) {
                Task {
                    await settingsViewModel.recalculateBalances()
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "alert.recalculateBalances.message"))
        }
        .alert(
            String(localized: "alert.deleteAllData.title"),
            isPresented: $showingResetConfirmation
        ) {
            Button(String(localized: "alert.deleteAllData.confirm"), role: .destructive) {
                Task {
                    await settingsViewModel.resetAllData()
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "alert.deleteAllData.message"))
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportActivityView(transactionsViewModel: transactionsViewModel)
        }
        .sheet(isPresented: $showingImportPicker) {
            DocumentPicker(contentTypes: [.commaSeparatedText, .text]) { url in
                Task {
                    await settingsViewModel.startImportFlow(from: url)
                }
            }
        }
        .task {
            // Load wallpaper on view appear
            await settingsViewModel.loadInitialData()
        }
    }

    // MARK: - Sections (Props-based Components)

    private var generalSection: some View {
        SettingsGeneralSection(
            selectedCurrency: settingsViewModel.settings.baseCurrency,
            availableCurrencies: AppSettings.availableCurrencies,
            hasWallpaper: settingsViewModel.currentWallpaper != nil,
            selectedPhoto: $selectedPhoto,
            onCurrencyChange: { newCurrency in
                Task {
                    await settingsViewModel.updateBaseCurrency(newCurrency)
                }
            },
            onPhotoChange: { newItem in
                #if DEBUG
                print("📸 [SettingsView] Photo picker changed, newItem: \(newItem != nil ? "present" : "nil")")
                #endif

                guard let newItem = newItem else {
                    #if DEBUG
                    print("⚠️ [SettingsView] No item selected")
                    #endif
                    return
                }

                guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                    #if DEBUG
                    print("❌ [SettingsView] Failed to load transferable data")
                    #endif
                    return
                }

                guard let image = UIImage(data: data) else {
                    #if DEBUG
                    print("❌ [SettingsView] Failed to create UIImage from data")
                    #endif
                    return
                }

                #if DEBUG
                print("✅ [SettingsView] Image loaded, calling selectWallpaper")
                #endif
                await settingsViewModel.selectWallpaper(image)

                // Reset selectedPhoto to allow selecting the same image again if needed
                selectedPhoto = nil
            },
            onWallpaperRemove: {
                await settingsViewModel.removeWallpaper()
            }
        )
    }

    private var dataManagementSection: some View {
        SettingsDataManagementSection {
            CategoriesManagementView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel
            )
        } subcategoriesDestination: {
            SubcategoriesManagementView(
                categoriesViewModel: categoriesViewModel
            )
        } accountsDestination: {
            AccountsManagementView(
                accountsViewModel: accountsViewModel,
                depositsViewModel: depositsViewModel,
                transactionsViewModel: transactionsViewModel
            )
        }
    }

    private var exportImportSection: some View {
        SettingsExportImportSection(
            onExport: {
                showingExportSheet = true
            },
            onImport: {
                showingImportPicker = true
            }
        )
    }

    private var dangerZoneSection: some View {
        SettingsDangerZoneSection(
            onRecalculateBalances: {
                showingRecalculateBalancesConfirmation = true
            },
            onResetData: {
                showingResetConfirmation = true
            }
        )
    }
}

// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    NavigationView {
        SettingsView(
            settingsViewModel: coordinator.settingsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            subscriptionsViewModel: coordinator.subscriptionsViewModel,
            depositsViewModel: coordinator.depositsViewModel
        )
    }
}
