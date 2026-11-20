//
//  AnalyticsConfigurationTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsConfigurationTests {

    private func makeConfiguration(
        batchSize: Int = AnalyticsLimits.defaultBatchEvents,
        maxRetries: Int = AnalyticsLimits.defaultRetries,
        maxSimultaneousRequests: Int = AnalyticsLimits.defaultSimultaneousRequests
    ) -> AnalyticsConfiguration {

        AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: batchSize,
            maxRetries: maxRetries,
            maxSimultaneousRequests: maxSimultaneousRequests
        )
    }

    // MARK: - Default Values

    @Test("Configuration uses default limits")
    func testDefaultValues() {

        let configuration = makeConfiguration()

        #expect(configuration.batchSize == 20)
        #expect(configuration.maxRetries == 4)
        #expect(configuration.maxSimultaneousRequests == 2)
    }

    // MARK: - Batch Size

    @Test("Batch size cannot be lower than minimum")
    func testMinimumBatchSize() {

        let configuration = makeConfiguration(batchSize: 0)

        #expect(
            configuration.batchSize
            == AnalyticsLimits.minBatchEvents
        )
    }

    @Test("Batch size cannot exceed maximum")
    func testMaximumBatchSize() {

        let configuration = makeConfiguration(batchSize: 100)

        #expect(
            configuration.batchSize
            == AnalyticsLimits.maxBatchEvents
        )
    }

    // MARK: - Retries

    @Test("Retry count cannot be negative")
    func testMinimumRetries() {

        let configuration = makeConfiguration(maxRetries: -5)

        #expect(
            configuration.maxRetries
            == AnalyticsLimits.minRetries
        )
    }

    @Test("Retry count cannot exceed maximum")
    func testMaximumRetries() {

        let configuration = makeConfiguration(maxRetries: 10)

        #expect(
            configuration.maxRetries
            == AnalyticsLimits.maxRetries
        )
    }

    // MARK: - Concurrent Requests

    @Test("Concurrent requests cannot be lower than one")
    func testMinimumConcurrentRequests() {

        let configuration = makeConfiguration(
            maxSimultaneousRequests: 0
        )

        #expect(
            configuration.maxSimultaneousRequests
            == AnalyticsLimits.minSimultaneousRequests
        )
    }

    @Test("Concurrent requests cannot exceed four")
    func testMaximumConcurrentRequests() {

        let configuration = makeConfiguration(
            maxSimultaneousRequests: 10
        )

        #expect(
            configuration.maxSimultaneousRequests
            == AnalyticsLimits.maxSimultaneousRequests
        )
    }
}
