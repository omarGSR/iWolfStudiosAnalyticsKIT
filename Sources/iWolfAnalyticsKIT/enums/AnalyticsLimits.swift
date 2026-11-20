//
//  AnalyticsLimits.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

public enum AnalyticsLimits {
    
    // Batch
    
    /// This value should be same configured in BE
    /// AnalyticsContract.php
    /// MAX_BATCH_EVENTS = 30;
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
}
