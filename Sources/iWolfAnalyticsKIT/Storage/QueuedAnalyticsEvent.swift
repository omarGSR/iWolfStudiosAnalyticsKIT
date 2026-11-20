//
//  QueuedAnalyticsEvent.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Represents an analytics event stored in the persistent queue.
struct QueuedAnalyticsEvent: Codable, Sendable {

    /// Original event sent to the backend.
    let event: AnalyticsEvent

    /// Number of retries performed after an initial attempt.
    private(set) var retryCount: Int

    init(
        event: AnalyticsEvent,
        retryCount: Int = 0
    ) {
        self.event = event
        self.retryCount = max(0, retryCount)
    }

    /// Increments the retry counter.
    mutating func incrementRetryCount() {
        retryCount += 1
    }

    /// Indicates whether another retry is allowed.
    func canRetry(maxRetries: Int) -> Bool {
        retryCount < max(0, maxRetries)
    }
}
