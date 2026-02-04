//
//  ImportFlowSheetsContainer.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based container for Import Flow sheets
/// Single Responsibility: Manage all import flow sheet presentations based on coordinator state
struct ImportFlowSheetsContainer<Content: View>: View {
    // MARK: - Props

    let flowCoordinator: ImportFlowCoordinator?
    let onCancel: () -> Void
    let content: Content

    // MARK: - Initializer

    init(
        flowCoordinator: ImportFlowCoordinator?,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.flowCoordinator = flowCoordinator
        self.onCancel = onCancel
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        content
            // Preview Sheet
            .sheet(isPresented: Binding(
                get: {
                    if case .preview = flowCoordinator?.currentStep {
                        return true
                    }
                    return false
                },
                set: { if !$0 { onCancel() } }
            )) {
                previewSheet
            }
            // Column Mapping Sheet
            .sheet(isPresented: Binding(
                get: {
                    if case .columnMapping = flowCoordinator?.currentStep {
                        return true
                    }
                    return false
                },
                set: { if !$0 { onCancel() } }
            )) {
                columnMappingSheet
            }
            // Progress Sheet
            .sheet(isPresented: Binding(
                get: {
                    if case .importing = flowCoordinator?.currentStep {
                        return true
                    }
                    return false
                },
                set: { _ in }
            )) {
                progressSheet
            }
            // Result Sheet
            .sheet(isPresented: Binding(
                get: {
                    if case .result = flowCoordinator?.currentStep {
                        return true
                    }
                    return false
                },
                set: { if !$0 { onCancel() } }
            )) {
                resultSheet
            }
            // Error Alert
            .alert(String(localized: "alert.importError.title"), isPresented: Binding(
                get: {
                    if case .error = flowCoordinator?.currentStep {
                        return true
                    }
                    return false
                },
                set: { if !$0 { onCancel() } }
            )) {
                Button(String(localized: "button.ok"), role: .cancel) {
                    onCancel()
                }
            } message: {
                if let errorMessage = flowCoordinator?.errorMessage {
                    Text(errorMessage)
                }
            }
    }

    // MARK: - Sheets

    @ViewBuilder
    private var previewSheet: some View {
        if let flowCoordinator = flowCoordinator,
           let csvFile = flowCoordinator.csvFile {
            CSVPreviewView(
                csvFile: csvFile,
                onContinue: {
                    flowCoordinator.continueToColumnMapping()
                },
                onCancel: onCancel
            )
        }
    }

    @ViewBuilder
    private var columnMappingSheet: some View {
        if let flowCoordinator = flowCoordinator,
           let csvFile = flowCoordinator.csvFile {
            CSVColumnMappingView(
                csvFile: csvFile,
                onComplete: { mapping in
                    flowCoordinator.columnMapping = mapping
                    Task {
                        await flowCoordinator.performImport()
                    }
                },
                onCancel: onCancel
            )
        }
    }

    @ViewBuilder
    private var progressSheet: some View {
        if let flowCoordinator = flowCoordinator,
           let progress = flowCoordinator.importProgress {
            ImportProgressSheet(
                currentRow: progress.currentRow,
                totalRows: progress.totalRows,
                progress: progress.progress,
                onCancel: {
                    progress.cancel()
                    onCancel()
                }
            )
        }
    }

    @ViewBuilder
    private var resultSheet: some View {
        if let flowCoordinator = flowCoordinator,
           let result = flowCoordinator.importResult {
            CSVImportResultView(
                statistics: result,
                onDone: onCancel,
                onViewErrors: nil
            )
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var flowCoordinator = ImportFlowCoordinator(
            transactionsViewModel: nil,
            categoriesViewModel: nil,
            accountsViewModel: nil
        )

        var body: some View {
            ImportFlowSheetsContainer(
                flowCoordinator: flowCoordinator,
                onCancel: {
                    print("Cancel import flow")
                }
            ) {
                Text("Main Content")
            }
        }
    }

    return PreviewWrapper()
}
