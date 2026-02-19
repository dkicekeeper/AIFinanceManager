//
//  TabViews.swift
//  AIFinanceManager
//
//  NavigationStack wrappers for each tab in MainTabView.
//  Each wrapper owns its NavigationStack so navigation state
//  is independent per tab (standard iOS tab bar pattern).
//

import SwiftUI

// MARK: - HomeTab

struct HomeTab: View {
    var body: some View {
        ContentView()
    }
}

// MARK: - AnalyticsTab

struct AnalyticsTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    var body: some View {
        NavigationStack {
            InsightsView(insightsViewModel: coordinator.insightsViewModel)
                .environment(timeFilterManager)
                .navigationTitle(String(localized: "tab.analytics"))
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - SettingsTab

struct SettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            SettingsView(
                settingsViewModel: coordinator.settingsViewModel,
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                transactionStore: coordinator.transactionStore,
                depositsViewModel: coordinator.depositsViewModel
            )
        }
    }
}

// MARK: - VoiceTab

/// Full-screen voice recording tab.
/// VoiceInputView is embedded directly — no button trigger needed.
/// After recognition completes, pushes to VoiceInputConfirmationView.
struct VoiceTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var voiceService = VoiceInputService()
    @State private var parsedOperation: ParsedOperation? = nil

    private var parser: VoiceInputParser {
        VoiceInputParser(
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }

    var body: some View {
        NavigationStack {
            VoiceInputView(
                voiceService: voiceService,
                onComplete: { transcribedText in
                    let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    parsedOperation = parser.parse(trimmed)
                },
                parser: parser,
                embeddedInTab: true
            )
            .navigationDestination(item: $parsedOperation) { parsed in
                VoiceInputConfirmationView(
                    transactionsViewModel: coordinator.transactionsViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel,
                    parsedOperation: parsed,
                    originalText: voiceService.getFinalText()
                )
            }
            .onAppear {
                voiceService.categoriesViewModel = coordinator.categoriesViewModel
                voiceService.accountsViewModel = coordinator.accountsViewModel
            }
        }
    }
}

// MARK: - OCRTab

/// Full-screen OCR / PDF import tab.
/// Shows a centred import prompt; PDFImportCoordinator handles the rest internally.
struct OCRTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                // Icon
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "tab.ocr"))
                        .font(AppTypography.h3)

                    Text(String(localized: "accessibility.importStatementHint"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxxl)
                }

                // PDFImportCoordinator renders the import button + manages all sheets
                PDFImportCoordinator(
                    transactionsViewModel: coordinator.transactionsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel
                )

                Spacer()
            }
            .navigationTitle(String(localized: "tab.ocr"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
