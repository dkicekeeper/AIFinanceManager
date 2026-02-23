//
//  TransactionPaginationController.swift
//  AIFinanceManager
//
//  Created on 2026-02-23
//  Task 9: Paginated, sectioned transaction access via NSFetchedResultsController
//
//  Design decisions:
//  - TransactionStore remains SSOT for mutations; this controller is read-only.
//  - fetchBatchSize = 50: only visible batch is materialized in memory (vs all 19k).
//  - sectionNameKeyPath = "dateSectionKey": CoreData-native grouping by day.
//  - cacheName = "transactions-main": disk-cached section index for fast reload.
//  - Filters trigger NSFetchedResultsController.deleteCache + re-fetch.
//

import Foundation
import CoreData
import Observation
import os

// MARK: - Supporting Types

/// A single date-grouped section of transactions for display in a list.
struct TransactionSection: Identifiable {
    /// "YYYY-MM-DD" — unique per calendar day, doubles as the section identifier.
    let id: String
    /// Human-readable date string (same value as id; views may format it further).
    let date: String
    let transactions: [Transaction]

    init(date: String, transactions: [Transaction]) {
        self.id = date
        self.date = date
        self.transactions = transactions
    }
}

// MARK: - TransactionPaginationController

/// Manages paginated, sectioned transaction display via NSFetchedResultsController.
///
/// Exposes `sections` and `totalCount` as observable state consumed by SwiftUI views.
/// Setting any filter property automatically re-fetches and updates the observable state.
///
/// TransactionStore remains the single source of truth for all mutations.
/// This class is purely a read-optimized presentation layer over CoreData.
@Observable @MainActor
final class TransactionPaginationController: NSObject {

    // MARK: - Observable State

    /// Date-sectioned transactions ready for list display.
    private(set) var sections: [TransactionSection] = []

    /// Total number of transactions matching current filters (pre-pagination).
    private(set) var totalCount: Int = 0

    // MARK: - Filters
    // Each didSet invalidates the FRC cache and triggers a re-fetch.

    var searchQuery: String = "" {
        didSet { if searchQuery != oldValue { scheduleFilterUpdate() } }
    }

    var selectedAccountId: String? {
        didSet { if selectedAccountId != oldValue { scheduleFilterUpdate() } }
    }

    var selectedCategoryId: String? {
        didSet { if selectedCategoryId != oldValue { scheduleFilterUpdate() } }
    }

    var selectedType: TransactionType? {
        didSet { if selectedType != oldValue { scheduleFilterUpdate() } }
    }

    var dateRange: (start: Date, end: Date)? {
        didSet { scheduleFilterUpdate() }
    }

    // MARK: - Private

    @ObservationIgnored private var frc: NSFetchedResultsController<TransactionEntity>?
    @ObservationIgnored private let stack: CoreDataStack
    @ObservationIgnored private let logger = Logger(
        subsystem: "AIFinanceManager",
        category: "TransactionPaginationController"
    )

    // MARK: - Init

    init(stack: CoreDataStack) {
        self.stack = stack
    }

    // MARK: - Setup

    /// Configures the NSFetchedResultsController and performs the initial fetch.
    /// Must be called once after initialisation (called by AppCoordinator.initialize()).
    func setup() {
        let request = TransactionEntity.fetchRequest()
        // Sort descending by date so newest transactions appear first.
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        // Fetch in batches of 50 — only rows visible on screen are faulted into memory.
        request.fetchBatchSize = 50
        // Keep objects as faults until their properties are accessed.
        request.returnsObjectsAsFaults = true

        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: stack.viewContext,
            sectionNameKeyPath: "dateSectionKey",
            cacheName: "transactions-main"
        )
        frc?.delegate = self

        performFetch()
    }

    // MARK: - Filter Application

    private func scheduleFilterUpdate() {
        // Must delete named cache before changing fetchRequest.predicate;
        // otherwise NSFetchedResultsController re-uses stale section metadata.
        NSFetchedResultsController<TransactionEntity>.deleteCache(withName: "transactions-main")
        applyCurrentFilters()
    }

    private func applyCurrentFilters() {
        var predicates: [NSPredicate] = []

        if !searchQuery.isEmpty {
            let q = searchQuery
            predicates.append(NSPredicate(
                format: "descriptionText CONTAINS[cd] %@ OR category CONTAINS[cd] %@",
                q, q
            ))
        }

        if let accountId = selectedAccountId {
            predicates.append(NSPredicate(format: "accountId == %@", accountId))
        }

        if let categoryId = selectedCategoryId {
            // category stores the category name/id string on TransactionEntity
            predicates.append(NSPredicate(format: "category == %@", categoryId))
        }

        if let type = selectedType {
            predicates.append(NSPredicate(format: "type == %@", type.rawValue))
        }

        if let range = dateRange {
            predicates.append(NSPredicate(
                format: "date >= %@ AND date <= %@",
                range.start as NSDate,
                range.end as NSDate
            ))
        }

        frc?.fetchRequest.predicate = predicates.isEmpty
            ? nil
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        performFetch()
    }

    // MARK: - Fetch Execution

    private func performFetch() {
        guard let frc else { return }
        do {
            try frc.performFetch()
            rebuildSections()
        } catch {
            logger.error("FRC performFetch failed: \(error.localizedDescription)")
        }
    }

    private func rebuildSections() {
        guard let frcSections = frc?.sections else {
            sections = []
            totalCount = 0
            return
        }

        sections = frcSections.map { section in
            let transactions = (section.objects as? [TransactionEntity] ?? [])
                .compactMap { $0.toTransaction() }
            return TransactionSection(
                date: section.name,
                transactions: transactions
            )
        }
        totalCount = frc?.fetchedObjects?.count ?? 0
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension TransactionPaginationController: NSFetchedResultsControllerDelegate {
    /// Called on whatever thread the context uses — bridge back to MainActor for state mutation.
    nonisolated func controllerDidChangeContent(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>
    ) {
        Task { @MainActor [weak self] in
            self?.rebuildSections()
        }
    }
}
