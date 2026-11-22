//
//  AnalyticsConfiguration.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Configuration used to initialize iWolfAnalyticsKit.
public struct AnalyticsConfiguration: Sendable {

    public let baseURL: URL
    public let appKey: String
    public let batchSize: Int
    public let maxRetries: Int
    public let maxSimultaneousRequests: Int
    
    public let syncIntervalScheduler: TimeInterval
    public let minEventsToSyncScheduler: Int
    public let forcedSyncIntervalScheduler: TimeInterval
    
    /// Creates an analytics configuration with customizable batching,
    /// retry limits, concurrent requests, and automatic synchronization.
    ///
    /// All values are automatically clamped to their supported ranges.
    /// Synchronization intervals are expressed in seconds.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL of the analytics API.
    ///   - appKey: Unique application identifier.
    ///   - batchSize: Maximum number of events per HTTP request.
    ///   - maxRetries: Maximum retry attempts for rejected events.
    ///   - maxSimultaneousRequests: Maximum concurrent HTTP requests.
    ///   - syncIntervalScheduler: Interval between automatic sync checks.
    ///   - minEventsToSyncScheduler: Minimum pending events required for automatic sync.
    ///   - forcedSyncIntervalScheduler: Maximum waiting interval before forcing a sync.
    public init(
        baseURL: URL = URL(
            string: "https://api.iwolfstudios.io"
        )!,
        appKey: String = Bundle.main.bundleIdentifier ?? "",
        batchSize: Int = AnalyticsLimits.defaultBatchEvents,
        maxRetries: Int = AnalyticsLimits.defaultRetries,
        maxSimultaneousRequests: Int = AnalyticsLimits.defaultSimultaneousRequests,
        syncIntervalScheduler: TimeInterval = AnalyticsLimits.defaultSchedulerSyncInterval,
        minEventsToSyncScheduler: Int = AnalyticsLimits.defaultSchedulerMinEventsToSync,
        forcedSyncIntervalScheduler: TimeInterval = AnalyticsLimits.defaultForcedSyncMaxInterval
    ) {
        self.baseURL = baseURL
        self.appKey = appKey

        self.batchSize = min(
            max(batchSize, AnalyticsLimits.minBatchEvents),
            AnalyticsLimits.maxBatchEvents
        )

        self.maxRetries = min(
            max(maxRetries, AnalyticsLimits.minRetries),
            AnalyticsLimits.maxRetries
        )
        
        self.maxSimultaneousRequests = min(
            max(
                maxSimultaneousRequests,
                AnalyticsLimits.minSimultaneousRequests
            ),
            AnalyticsLimits.maxSimultaneousRequests
        )
        
        self.forcedSyncIntervalScheduler = min(
            max(forcedSyncIntervalScheduler, AnalyticsLimits.defaultForcedSyncMaxInterval / 4),
            AnalyticsLimits.defaultForcedSyncMaxInterval * 2
        )
        
        self.syncIntervalScheduler = min(
            max(syncIntervalScheduler, 5),
            self.forcedSyncIntervalScheduler / 2
        )
        
        self.minEventsToSyncScheduler = min(
            max(minEventsToSyncScheduler, 1),
            max(self.batchSize - 1, 1)
        )
    }
}
