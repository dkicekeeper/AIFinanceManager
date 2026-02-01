//
//  PDFImportCoordinator.swift
//  AIFinanceManager
//
//  PDF import flow coordinator - handles file picker, OCR, and CSV preview
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI
import PDFKit

/// Coordinates the entire PDF import flow: file picker → OCR → recognized text → CSV preview
/// Single responsibility: PDF import orchestration
struct PDFImportCoordinator: View {
    // MARK: - Dependencies
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel

    // MARK: - State
    @State private var showingFilePicker = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var recognizedText: String? = nil
    @State private var structuredRows: [[String]]? = nil
    @State private var showingRecognizedText = false
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil

    // MARK: - Body
    var body: some View {
        importButton
            .sheet(isPresented: $showingFilePicker) {
                filePicker
            }
            .sheet(isPresented: $showingRecognizedText) {
                recognizedTextSheet
            }
            .sheet(isPresented: $showingCSVPreview) {
                csvPreviewSheet
            }
            .overlay {
                if transactionsViewModel.isLoading {
                    loadingOverlay
                }
            }
    }

    // MARK: - Import Button
    private var importButton: some View {
        Button(action: {
            HapticManager.light()
            showingFilePicker = true
        }) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: AppIconSize.lg))
                .fontWeight(.semibold)
                .frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(String(localized: LocalizationKeys.Accessibility.importStatement))
        .accessibilityHint(String(localized: LocalizationKeys.Accessibility.importStatementHint))
    }

    // MARK: - File Picker
    private var filePicker: some View {
        DocumentPicker { url in
            Task {
                await analyzePDF(url: url)
            }
        }
    }

    // MARK: - Recognized Text Sheet
    @ViewBuilder
    private var recognizedTextSheet: some View {
        if let text = recognizedText, !text.isEmpty {
            RecognizedTextView(
                recognizedText: text,
                structuredRows: structuredRows,
                viewModel: transactionsViewModel,
                onImport: { csvFile in
                    showingRecognizedText = false
                    recognizedText = nil
                    structuredRows = nil
                    // Open CSVPreviewView for continued import
                    showingCSVPreview = true
                    parsedCSVFile = csvFile
                },
                onCancel: {
                    showingRecognizedText = false
                    recognizedText = nil
                    structuredRows = nil
                    transactionsViewModel.isLoading = false
                }
            )
        } else {
            // Fallback - empty screen if text not loaded
            NavigationView {
                VStack(spacing: AppSpacing.md) {
                    Text(String(localized: LocalizationKeys.Error.loadTextFailed))
                        .font(AppTypography.h4)
                    Text(String(localized: LocalizationKeys.Error.tryAgain))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - CSV Preview Sheet
    @ViewBuilder
    private var csvPreviewSheet: some View {
        if let csvFile = parsedCSVFile {
            CSVPreviewView(
                csvFile: csvFile,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel
            )
        }
    }

    // MARK: - Loading Overlay
    @ViewBuilder
    private var loadingOverlay: some View {
        VStack(spacing: AppSpacing.md) {
            if let progress = ocrProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                    Text(String(localized: LocalizationKeys.Progress.recognizingText))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
                Text(String(format: String(localized: LocalizationKeys.Progress.page), progress.current, progress.total))
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            } else {
                ProgressView(String(localized: LocalizationKeys.Progress.processingPDF))
            }
        }
        .padding(AppSpacing.md)
        .glassCardStyle()
    }

    // MARK: - PDF Analysis
    private func analyzePDF(url: URL) async {
        await MainActor.run {
            transactionsViewModel.isLoading = true
            transactionsViewModel.errorMessage = nil
            ocrProgress = nil
            recognizedText = nil
        }

        do {
            // Extract text via PDFKit or OCR
            let ocrResult = try await PDFService.shared.extractText(from: url) { current, total in
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }

            // Check that text is not empty
            let trimmedText = ocrResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                await MainActor.run {
                    transactionsViewModel.errorMessage = String(localized: LocalizationKeys.Error.pdfExtraction)
                    transactionsViewModel.isLoading = false
                    ocrProgress = nil
                }
                return
            }

            await MainActor.run {
                recognizedText = ocrResult.fullText
                structuredRows = ocrResult.structuredRows
                ocrProgress = nil
                transactionsViewModel.isLoading = false
                showingRecognizedText = true
            }

        } catch let error as PDFError {
            let errorMessage = error.localizedDescription
            await MainActor.run {
                transactionsViewModel.errorMessage = errorMessage
                transactionsViewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        } catch {
            await MainActor.run {
                transactionsViewModel.errorMessage = String(
                    format: String(localized: LocalizationKeys.Error.pdfRecognitionFailed),
                    error.localizedDescription
                )
                transactionsViewModel.isLoading = false
                ocrProgress = nil
                recognizedText = nil
                structuredRows = nil
            }
        }
    }
}
