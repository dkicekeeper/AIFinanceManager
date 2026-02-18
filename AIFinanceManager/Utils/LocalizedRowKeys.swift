//
//  LocalizedRowKeys.swift
//  AIFinanceManager
//
//  Centralized localization keys for row components
//  Created: 2026-02-16
//
//  Usage:
//  ```swift
//  Button(LocalizedRowKey.delete.localized, systemImage: "trash")
//  Text(LocalizedRowKey.edit.localized)
//  ```
//

import Foundation

/// Centralized localization keys for row components and common UI elements
/// Provides type-safe access to localized strings
enum LocalizedRowKey: String {
    // MARK: - Actions

    case delete = "button.delete"
    case edit = "button.edit"
    case select = "button.select"
    case change = "button.change"
    case save = "button.save"
    case cancel = "button.cancel"
    case done = "button.done"
    case add = "button.add"
    case remove = "button.remove"

    // MARK: - Hero Section (Phase 16)

    case tapIconToChange = "hero.tapIconToChange"

    // MARK: - Settings

    case settings = "settings.title"
    case categories = "settings.categories"
    case accounts = "settings.accounts"
    case exportData = "settings.exportData"
    case importData = "settings.importData"
    case recalculateBalances = "settings.recalculateBalances"
    case resetData = "settings.resetData"
    case wallpaper = "settings.wallpaper"

    // MARK: - Common Labels

    case frequency = "common.frequency"
    case startDate = "common.startDate"
    case endDate = "common.endDate"
    case icon = "common.icon"
    case logo = "common.logo"
    case color = "common.color"
    case name = "common.name"
    case amount = "common.amount"
    case description = "common.description"

    // MARK: - Category

    case category = "category.title"
    case noBudgetSet = "No budget set"

    // MARK: - Account

    case account = "account.title"
    case interestToday = "account.interestToday"
    case nextPosting = "account.nextPosting"

    // MARK: - Transaction (Phase 16)

    case makeRecurring = "transactionForm.makeRecurring"

    // Transaction Preview (CSV import)
    case transactionPreviewTitle = "navigation.transactionPreview"
    case transactionPreviewFound = "transactionPreview.found"
    case transactionPreviewSelectHint = "transactionPreview.selectHint"
    case transactionPreviewSelectAll = "transactionPreview.selectAll"
    case transactionPreviewDeselectAll = "transactionPreview.deselectAll"
    case transactionPreviewAddSelected = "transactionPreview.addSelected"
    case transactionPreviewNoAccount = "transactionPreview.noAccount"
    case transactionPreviewAccount = "transactionPreview.account"

    // MARK: - Subscription

    case subscription = "subscription.title"
    case basicInfo = "subscription.basicInfo"
    case namePlaceholder = "subscription.namePlaceholder"
    case reminders = "subscription.reminders"

    // MARK: - Recurring

    case never = "recurring.never"

    // MARK: - Reminder

    case none = "reminder.none"
    case dayBefore = "reminder.dayBefore.one"
    case daysBefore3 = "reminder.daysBefore.3"
    case daysBefore7 = "reminder.daysBefore.7"
    case daysBefore30 = "reminder.daysBefore.30"

    // MARK: - Carousel Empty States

    case noAccountsAvailable = "emptyState.noAccounts"
    case noSubcategoriesAvailable = "emptyState.noSubcategories"
    case noCategoriesAvailable = "emptyState.noCategories"
    case noDataAvailable = "emptyState.noData"

    // MARK: - Carousel Titles

    case selectAccount = "common.selectAccount"
    case selectCategory = "common.selectCategory"
    case selectSubcategory = "common.selectSubcategory"
    case selectColor = "common.selectColor"
    case filterBy = "common.filterBy"

    // MARK: - Filter Buttons (Phase 14)

    case allAccounts = "filter.allAccounts"
    case allCategories = "filter.allCategories"
    case categoriesCount = "filter.categoriesCount"

    // MARK: - Animated Input (Phase 16)

    case amountPlaceholder = "input.amountPlaceholder"
    case titleHint = "input.titleHint"
    case balanceHint = "input.balanceHint"

    // MARK: - Insights (Phase 17)

    case insightsTitle = "insights.title"
    case insightsSpending = "insights.spending"
    case insightsIncome = "insights.income"
    case insightsBudget = "insights.budget"
    case insightsRecurring = "insights.recurring"
    case insightsCashFlow = "insights.cashFlow"

    // MARK: - CSV Specific

    case csvEmptyCell = "csv.emptyCell"

    // MARK: - Computed Property

    /// Returns localized string for the key
    var localized: String {
        String(localized: LocalizedStringResource(stringLiteral: rawValue))
    }

    /// Returns localized string with format arguments
    /// - Parameter arguments: Format arguments
    /// - Returns: Formatted localized string
    func localized(with arguments: CVarArg...) -> String {
        let format = String(localized: LocalizedStringResource(stringLiteral: rawValue))
        return String(format: format, arguments: arguments)
    }
}

// MARK: - Convenience Extensions

extension LocalizedRowKey {
    /// Common button labels
    static let commonButtons: [LocalizedRowKey] = [
        .delete, .edit, .select, .change, .save, .cancel, .done, .add, .remove
    ]

    /// Settings-related keys
    static let settingsKeys: [LocalizedRowKey] = [
        .settings, .categories, .accounts, .exportData, .importData,
        .recalculateBalances, .resetData, .wallpaper
    ]

    /// Form field labels
    static let formFields: [LocalizedRowKey] = [
        .frequency, .startDate, .endDate, .icon, .logo, .color,
        .name, .amount, .description
    ]

    /// Carousel-related keys
    static let carouselKeys: [LocalizedRowKey] = [
        .noAccountsAvailable, .noSubcategoriesAvailable, .noCategoriesAvailable,
        .noDataAvailable, .selectAccount, .selectCategory, .selectSubcategory,
        .selectColor, .filterBy, .csvEmptyCell
    ]

    /// Filter button keys (Phase 14)
    static let filterKeys: [LocalizedRowKey] = [
        .allAccounts, .allCategories, .categoriesCount
    ]

    /// Transaction preview keys (Phase 16)
    static let transactionPreviewKeys: [LocalizedRowKey] = [
        .transactionPreviewTitle, .transactionPreviewFound, .transactionPreviewSelectHint,
        .transactionPreviewSelectAll, .transactionPreviewDeselectAll,
        .transactionPreviewAddSelected, .transactionPreviewNoAccount, .transactionPreviewAccount
    ]
}

// MARK: - Preview Helper

#if DEBUG
extension LocalizedRowKey {
    /// Returns all localization keys for testing
    static var allCases: [LocalizedRowKey] {
        return [
            // Actions
            .delete, .edit, .select, .change, .save, .cancel, .done, .add, .remove,

            // Settings
            .settings, .categories, .accounts, .exportData, .importData,
            .recalculateBalances, .resetData, .wallpaper,

            // Common
            .frequency, .startDate, .endDate, .icon, .logo, .color,
            .name, .amount, .description,

            // Domain-specific
            .category, .noBudgetSet, .account, .interestToday, .nextPosting,
            .makeRecurring, .subscription, .basicInfo, .namePlaceholder,
            .reminders, .never, .none, .dayBefore, .daysBefore3,
            .daysBefore7, .daysBefore30,

            // Carousel
            .noAccountsAvailable, .noSubcategoriesAvailable, .noCategoriesAvailable,
            .noDataAvailable, .selectAccount, .selectCategory, .selectSubcategory,
            .selectColor, .filterBy, .csvEmptyCell,

            // Filter buttons
            .allAccounts, .allCategories, .categoriesCount,

            // Animated input
            .amountPlaceholder, .titleHint, .balanceHint,

            // Insights
            .insightsTitle, .insightsSpending, .insightsIncome,
            .insightsBudget, .insightsRecurring, .insightsCashFlow,

            // Transaction preview
            .transactionPreviewTitle, .transactionPreviewFound, .transactionPreviewSelectHint,
            .transactionPreviewSelectAll, .transactionPreviewDeselectAll,
            .transactionPreviewAddSelected, .transactionPreviewNoAccount, .transactionPreviewAccount
        ]
    }
}
#endif
