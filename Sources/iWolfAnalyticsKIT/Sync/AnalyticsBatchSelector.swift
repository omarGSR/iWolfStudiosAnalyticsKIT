//
//  AnalyticsBatchSelector.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//


import Foundation

/// Selects pending analytics events and groups them into batches.
enum AnalyticsBatchSelector {

    /// Returns batches in FIFO order, excluding events already in flight.
    static func select(
        from events: [QueuedAnalyticsEvent],
        batchSize: Int,
        maxBatches: Int,
        excluding inFlightIDs: Set<UUID> = []
    ) -> [[QueuedAnalyticsEvent]] {

        guard batchSize > 0, maxBatches > 0 else {
            return []
        }

        let maxEvents = batchSize.multipliedReportingOverflow(
            by: maxBatches
        )

        guard !maxEvents.overflow else {
            return []
        }

        var batches: [[QueuedAnalyticsEvent]] = []
        var currentBatch: [QueuedAnalyticsEvent] = []
        var selectedIDs = Set<UUID>()

        for queuedEvent in events {

            let id = queuedEvent.event.id

            guard !inFlightIDs.contains(id),
                  selectedIDs.insert(id).inserted else {
                continue
            }

            currentBatch.append(queuedEvent)

            if currentBatch.count == batchSize {
                batches.append(currentBatch)
                currentBatch = []

                if batches.count == maxBatches {
                    return batches
                }
            }
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }
}
