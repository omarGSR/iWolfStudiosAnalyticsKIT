//
//  AnalyticsLimits.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

public enum AnalyticsLimits {
    
    // Batch
    
    /// This value should be same configured in BE
    /// AnalyticsContract.php
    /// MAX_BATCH_EVENTS = 40;
    public static let maxBatchEvents: Int = 40
    
    public static let minBatchEvents: Int = 1
    public static let defaultBatchEvents: Int = 20
    
    // Retries
    
    public static let minRetries: Int = 0
    public static let maxRetries: Int  = 4
    public static let defaultRetries: Int = 4
    
    // Simultaneous request
    
    public static let minSimultaneousRequests = 1
    public static let maxSimultaneousRequests = 4
    public static let defaultSimultaneousRequests = 2
    
    // Policy Sync
    
    /// Send every 3 minutes if the queue has at least minEventsToSync events.
    public static let syncInterval: TimeInterval = 3 * 60
    public static let minEventsToSync: Int = 3
    
    /// Force synchronization after 15 minutes for small queues
    public static let forcedSyncInterval: TimeInterval = 15 * 60
}
