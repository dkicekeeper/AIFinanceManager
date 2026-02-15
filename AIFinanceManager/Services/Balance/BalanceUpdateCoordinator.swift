//
//  BalanceUpdateCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//
//  Actor for serializing balance update operations
//  Prevents race conditions when multiple sources try to update balances simultaneously

import Foundation

// MARK: - Balance Update Request

/// Represents a pending balance update request
struct BalanceUpdateRequest {
    let id: UUID = UUID()
    let source: BalanceUpdateSource
    let timestamp: Date = Date()
    let completion: (() -> Void)?

    enum BalanceUpdateSource {
        case transaction(id: String)
        case csvImport
        case subscription(seriesId: String)
        case manualRecalculation
        case accountCreation(accountId: String)
    }
}

// MARK: - Protocol

/// Protocol for balance update coordination
protocol BalanceUpdateCoordinatorProtocol: AnyObject {
    /// Schedule a balance update
    /// - Parameters:
    ///   - source: Source of the update
    ///   - action: The balance update action to perform
    ///   - completion: Called when update is complete
    func scheduleUpdate(
        source: BalanceUpdateRequest.BalanceUpdateSource,
        action: @escaping () async -> Void,
        completion: (() -> Void)?
    ) async

    /// Check if updates are currently being processed
    var isProcessing: Bool { get async }

    /// Cancel all pending updates (use with caution)
    func cancelAllPending() async
}

// MARK: - Actor Implementation

/// Actor that serializes balance update operations to prevent race conditions
actor BalanceUpdateCoordinator: BalanceUpdateCoordinatorProtocol {

    // MARK: - State

    private var pendingRequests: [BalanceUpdateRequest] = []
    private var isCurrentlyProcessing = false
    private var processedCount = 0
    private var lastProcessedTimestamp: Date?

    // MARK: - Public Properties

    var isProcessing: Bool {
        return isCurrentlyProcessing || !pendingRequests.isEmpty
    }

    // MARK: - Public Methods

    func scheduleUpdate(
        source: BalanceUpdateRequest.BalanceUpdateSource,
        action: @escaping () async -> Void,
        completion: (() -> Void)?
    ) async {
        let request = BalanceUpdateRequest(source: source, completion: completion)

        // Check for duplicate requests from same source (debouncing)
        if shouldDebounce(request) {
            return
        }

        pendingRequests.append(request)

        await processQueueIfNeeded(action: action)
    }

    func cancelAllPending() async {
        _ = pendingRequests.count
        pendingRequests.removeAll()
    }

    // MARK: - Private Methods

    private func shouldDebounce(_ request: BalanceUpdateRequest) -> Bool {
        // Debounce same source within 100ms
        guard let lastTimestamp = lastProcessedTimestamp else { return false }

        let timeSinceLastProcess = request.timestamp.timeIntervalSince(lastTimestamp)
        if timeSinceLastProcess < 0.1 {
            // Check if same source type
            for pending in pendingRequests {
                if isSameSource(pending.source, request.source) {
                    return true
                }
            }
        }

        return false
    }

    private func isSameSource(
        _ source1: BalanceUpdateRequest.BalanceUpdateSource,
        _ source2: BalanceUpdateRequest.BalanceUpdateSource
    ) -> Bool {
        switch (source1, source2) {
        case (.csvImport, .csvImport):
            return true
        case (.manualRecalculation, .manualRecalculation):
            return true
        case let (.transaction(id1), .transaction(id2)):
            return id1 == id2
        case let (.subscription(id1), .subscription(id2)):
            return id1 == id2
        case let (.accountCreation(id1), .accountCreation(id2)):
            return id1 == id2
        default:
            return false
        }
    }

    private func processQueueIfNeeded(action: @escaping () async -> Void) async {
        guard !isCurrentlyProcessing else {
            return
        }

        isCurrentlyProcessing = true
        defer {
            isCurrentlyProcessing = false
            lastProcessedTimestamp = Date()
        }

        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()

            await action()
            processedCount += 1

            // Call completion on main thread
            if let completion = request.completion {
                await MainActor.run {
                    completion()
                }
            }
        }
    }

    // MARK: - Debug

    func debugStats() -> (pending: Int, processed: Int, isProcessing: Bool) {
        return (pendingRequests.count, processedCount, isCurrentlyProcessing)
    }
}

// MARK: - Main Actor Wrapper

/// Wrapper for using BalanceUpdateCoordinator from main actor context
@MainActor
final class BalanceUpdateCoordinatorWrapper {
    private let coordinator = BalanceUpdateCoordinator()

    /// Schedule a balance update to be processed serially
    /// - Parameters:
    ///   - source: Source of the update
    ///   - action: The action to perform (will be called on main actor)
    ///   - completion: Called when complete
    func scheduleUpdate(
        source: BalanceUpdateRequest.BalanceUpdateSource,
        action: @escaping @MainActor () -> Void,
        completion: (() -> Void)? = nil
    ) {
        Task {
            await coordinator.scheduleUpdate(
                source: source,
                action: {
                    await MainActor.run {
                        action()
                    }
                },
                completion: completion
            )
        }
    }

    /// Check if updates are being processed
    var isProcessing: Bool {
        get async {
            await coordinator.isProcessing
        }
    }

    /// Cancel all pending updates
    func cancelAllPending() {
        Task {
            await coordinator.cancelAllPending()
        }
    }
}
