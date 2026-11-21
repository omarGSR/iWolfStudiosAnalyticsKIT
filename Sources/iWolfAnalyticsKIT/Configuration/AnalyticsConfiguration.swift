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

    public init(
        baseURL: URL = URL(
            string: "https://api.iwolfstudios.io"
        )!,
        appKey: String = Bundle.main.bundleIdentifier ?? "",
        batchSize: Int = AnalyticsLimits.defaultBatchEvents,
        maxRetries: Int = AnalyticsLimits.defaultRetries,
        maxSimultaneousRequests: Int = AnalyticsLimits.defaultSimultaneousRequests
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
    }
}
