//
//  BalanceUpdateQueue.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 2
//
//  Actor-based sequential queue for balance updates
//  Prevents race conditions through serial execution
//  Includes debouncing and priority scheduling
//

import Foundation

// MARK: - Balance Queue Request

/// Represents a balance update request for the queue
struct BalanceQueueRequest: Identifiable {
    let id: UUID
    let accountIds: Set<String>
    let operation: UpdateOperation
    let priority: Priority
    let timestamp: Date

    enum UpdateOperation {
        case transaction(TransactionUpdateOperation)
        case recalculateAll
        case recalculateAccounts(Set<String>)
    }

    enum Priority: Int, Comparable {
        case immediate = 0   // User interaction (optimistic update)
        case high = 1        // Manual transaction add/remove
        case normal = 2      // Background sync, subscription generation
        case low = 3         // Batch CSV import

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    init(
        accountIds: Set<String>,
        operation: UpdateOperation,
        priority: Priority = .normal,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.accountIds = accountIds
        self.operation = operation
        self.priority = priority
        self.timestamp = timestamp
    }

}

// MARK: - Balance Update Queue

/// Actor for sequential balance update processing
/// Prevents race conditions and ensures data consistency
actor BalanceUpdateQueue {

    // MARK: - Configuration

    private let debounceDuration: TimeInterval = 0.3  // 300ms
    private let maxQueueSize: Int = 1000

    // MARK: - State

    private var pendingUpdates: [BalanceQueueRequest] = []
    private var isProcessing: Bool = false
    private var debounceTimer: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    // MARK: - Statistics

    private var totalProcessed: Int = 0
    private var totalDebounced: Int = 0
    private var lastProcessedTime: Date?

    // MARK: - Public API

    /// Enqueue a balance update request
    /// - Parameter request: The update request to enqueue
    /// - Returns: true if request was enqueued, false if queue is full
    @discardableResult
    func enqueue(_ request: BalanceQueueRequest) async -> Bool {
        guard pendingUpdates.count < maxQueueSize else {
            #if DEBUG
            print("⚠️ BalanceUpdateQueue is full, dropping request")
            #endif
            return false
        }

        // Cancel previous debounce timer for low-priority requests
        if request.priority == .low || request.priority == .normal {
            debounceTimer?.cancel()
        }

        pendingUpdates.append(request)

        #if DEBUG
        print("📥 Enqueued update: \(request.id), priority: \(request.priority), queue size: \(pendingUpdates.count)")
        #endif

        // Immediate priority - process right away
        if request.priority == .immediate {
            await processQueue()
            return true
        }

        // High priority - short debounce (50ms)
        if request.priority == .high {
            debounceTimer = Task {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                await processQueue()
            }
            return true
        }

        // Normal/low priority - standard debounce (300ms)
        debounceTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDuration * 1_000_000_000))
            await processQueue()
        }

        return true
    }

    /// Process all pending updates in the queue
    func processQueue() async {
        guard !isProcessing, !pendingUpdates.isEmpty else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        #if DEBUG
        let startTime = Date()
        print("⚙️ Processing queue: \(pendingUpdates.count) updates")
        #endif

        // Sort by priority (immediate first, then high, normal, low)
        let sortedUpdates = pendingUpdates.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.priority < rhs.priority
        }

        // Process updates
        for update in sortedUpdates {
            await processUpdate(update)
            totalProcessed += 1
        }

        // Clear processed updates
        pendingUpdates.removeAll()
        lastProcessedTime = Date()

        #if DEBUG
        let duration = Date().timeIntervalSince(startTime)
        print("✅ Queue processed in \(Int(duration * 1000))ms, total: \(totalProcessed)")
        #endif
    }

    /// Force immediate processing of all pending updates
    /// Bypasses debouncing
    func flush() async {
        debounceTimer?.cancel()
        await processQueue()
    }

    /// Cancel all pending updates
    func cancelAll() {
        debounceTimer?.cancel()
        processingTask?.cancel()
        pendingUpdates.removeAll()

        #if DEBUG
        print("🚫 Cancelled all pending updates")
        #endif
    }

    /// Get queue statistics
    func getStatistics() -> QueueStatistics {
        return QueueStatistics(
            pendingCount: pendingUpdates.count,
            totalProcessed: totalProcessed,
            totalDebounced: totalDebounced,
            isProcessing: isProcessing,
            lastProcessedTime: lastProcessedTime
        )
    }

    // MARK: - Private Processing

    /// Process a single update request
    /// This is where we would call the actual balance calculation logic
    /// For now, it's a placeholder for the coordinator to implement
    private func processUpdate(_ update: BalanceQueueRequest) async {
        #if DEBUG
        print("  ⚙️ Processing update: \(update.id), operation: \(update.operation)")
        #endif

        // The actual balance calculation will be done by BalanceCoordinator
        // This queue just ensures sequential execution

        // Simulate processing time for testing
        #if DEBUG
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        #endif
    }
}

// MARK: - Queue Statistics

struct QueueStatistics {
    let pendingCount: Int
    let totalProcessed: Int
    let totalDebounced: Int
    let isProcessing: Bool
    let lastProcessedTime: Date?
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceUpdateQueue {
    /// Get pending updates for debugging
    func getPendingUpdates() -> [BalanceQueueRequest] {
        return pendingUpdates
    }

    /// Clear statistics
    func resetStatistics() {
        totalProcessed = 0
        totalDebounced = 0
        lastProcessedTime = nil
    }
}
#endif
