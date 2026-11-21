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

    /// Date when the event was added to the persistent queue.
    let enqueuedAt: Date

    // MARK: - Initialization

    init(
        event: AnalyticsEvent,
        retryCount: Int = 0,
        enqueuedAt: Date = Date()
    ) {
        self.event = event
        self.retryCount = max(0, retryCount)
        self.enqueuedAt = enqueuedAt
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case event
        case retryCount
        case enqueuedAt
    }

    init(from decoder: Decoder) throws {

        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        event = try container.decode(
            AnalyticsEvent.self,
            forKey: .event
        )

        retryCount = max(
            0,
            try container.decode(
                Int.self,
                forKey: .retryCount
            )
        )

        // Compatibility with queues persisted by older SDK versions.
        // Use the event occurrence date when enqueuedAt is missing.
        enqueuedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .enqueuedAt
        ) ?? event.occurredAt
    }

    // MARK: - Retry

    /// Increments the retry counter.
    mutating func incrementRetryCount() {
        retryCount += 1
    }

    /// Indicates whether another retry is allowed.
    func canRetry(maxRetries: Int) -> Bool {
        retryCount < max(0, maxRetries)
    }
}
