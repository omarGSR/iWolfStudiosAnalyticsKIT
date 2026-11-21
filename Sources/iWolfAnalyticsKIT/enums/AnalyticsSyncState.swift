//
//  AnalyticsSyncState.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation

/// Maintains synchronization state after global API errors.
///
/// This component does not modify events or their retry counters.
struct AnalyticsSyncState: Sendable {

    private(set) var effectiveBatchSize: Int
    private(set) var consecutiveFailures = 0
    private(set) var nextRetryAt: Date?
    private(set) var isStopped = false

    private let initialBatchSize: Int

    init(batchSize: Int) {
        let size = max(1, batchSize)

        self.initialBatchSize = size
        self.effectiveBatchSize = size
    }

    /// Indicates whether automatic synchronization is permitted.
    func canSync(at date: Date = Date()) -> Bool {
        guard !isStopped else {
            return false
        }

        guard let nextRetryAt else {
            return true
        }

        return date >= nextRetryAt
    }

    /// Applies a global error action.
    mutating func apply(
        _ action: AnalyticsGlobalErrorAction,
        at date: Date = Date()
    ) {

        switch action {

        case .retry:
            consecutiveFailures += 1

            // Exponential backoff: 30, 60, 120, 240...
            // Maximum delay: 15 minutes.
            let exponent = min(consecutiveFailures - 1, 5)
            let delay = min(
                30.0 * pow(2.0, Double(exponent)),
                900.0
            )

            nextRetryAt = date.addingTimeInterval(delay)

        case .stop:
            isStopped = true
            nextRetryAt = nil

        case .reduceBatchSize:
            effectiveBatchSize = max(
                1,
                effectiveBatchSize / 2
            )

            // Avoid immediately retrying an oversized batch.
            nextRetryAt = date.addingTimeInterval(30)
        }
    }

    /// Resets temporary failures after a successful request.
    mutating func recordSuccess() {
        consecutiveFailures = 0
        nextRetryAt = nil
    }

    /// Restores synchronization after a configuration problem
    /// has been resolved.
    mutating func resume() {
        isStopped = false
        consecutiveFailures = 0
        nextRetryAt = nil
    }

    /// Restores the configured batch size.
    mutating func resetBatchSize() {
        effectiveBatchSize = initialBatchSize
    }
}
