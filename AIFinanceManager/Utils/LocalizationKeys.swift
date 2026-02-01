//
//  LocalizationKeys.swift
//  AIFinanceManager
//
//  Centralized localization keys for type-safe string access
//

import Foundation

/// Centralized localization keys with compile-time safety
/// Usage: String(localized: LocalizationKeys.Accessibility.voiceInput)
enum LocalizationKeys {
    // MARK: - Accessibility
    enum Accessibility {
        static let voiceInput = "accessibility.voiceInput"
        static let voiceInputHint = "accessibility.voiceInputHint"
        static let importStatement = "accessibility.importStatement"
        static let importStatementHint = "accessibility.importStatementHint"
        static let calendar = "accessibility.calendar"
        static let calendarHint = "accessibility.calendarHint"
        static let settings = "accessibility.settings"
        static let settingsHint = "accessibility.settingsHint"
    }

    // MARK: - Progress
    enum Progress {
        static let loadingData = "progress.loadingData"
        static let recognizingText = "progress.recognizingText"
        static let page = "progress.page"
        static let processingPDF = "progress.processingPDF"
    }

    // MARK: - Empty States
    enum EmptyState {
        static let noAccounts = "emptyState.noAccounts"
        static let noTransactions = "emptyState.noTransactions"
    }

    // MARK: - Error Messages
    enum Error {
        static let pdfExtraction = "error.pdfExtraction"
        static let pdfRecognitionFailed = "error.pdfRecognitionFailed"
        static let loadTextFailed = "error.loadTextFailed"
        static let tryAgain = "error.tryAgain"
    }

    // MARK: - Navigation
    enum Navigation {
        static let accountsTitle = "accounts.title"
        static let analyticsHistory = "analytics.history"
    }
}
