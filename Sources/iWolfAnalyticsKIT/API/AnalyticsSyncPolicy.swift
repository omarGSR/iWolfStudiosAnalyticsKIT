//
//  AnalyticsSyncPolicy.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation

/// Defines when automatic analytics synchronization
/// should be requested.
struct AnalyticsSyncPolicy: Sendable {

    let syncInterval: TimeInterval
    let minEventsToSync: Int
    let forcedSyncInterval: TimeInterval

    init(configuration: AnalyticsConfiguration) {
        self.syncInterval = configuration.syncIntervalScheduler
        self.minEventsToSync = configuration.minEventsToSyncScheduler
        self.forcedSyncInterval = configuration.forcedSyncIntervalScheduler
    }

    /// Evaluates whether an automatic sync is due.
    ///
    /// - Parameters:
    ///   - pendingEvents: Number of queued events.
    ///   - effectiveBatchSize: Current batch size from SyncManager.
    ///   - oldestPendingAge: Seconds since the oldest
    ///     pending event was enqueued.
    ///   - canSync: Whether SyncManager currently permits syncing.
    func shouldSync(
        pendingEvents: Int,
        effectiveBatchSize: Int,
        oldestPendingAge: TimeInterval,
        canSync: Bool
    ) -> Bool {

        guard canSync, pendingEvents > 0 else {
            return false
        }

        // A full batch is sent immediately.
        if pendingEvents >= max(1, effectiveBatchSize) {
            return true
        }

        // Send smaller batches after the normal interval.
        if pendingEvents >= minEventsToSync {
            return oldestPendingAge >= syncInterval
        }

        // Force delivery of low-volume queues.
        return oldestPendingAge >= forcedSyncInterval
    }
}
