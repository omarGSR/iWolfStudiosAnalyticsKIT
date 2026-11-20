//
//  AnalyticsSyncManagerTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsSyncManagerTests {

    @Test("Sync completes with an empty queue")
    func testSyncWithEmptyQueue() async throws {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest"
        )

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let apiClient = AnalyticsAPIClient(
            baseURL: configuration.baseURL
        )

        let syncManager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: apiClient
        )

        await syncManager.sync()

        let pendingCount = await queue.count()

        #expect(pendingCount == 0)
    }
    
    @Test("Reserved events cannot be selected twice")
    func testInFlightEventsAreNotDuplicated() async throws {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        for index in 0..<10 {
            try await queue.enqueue(
                AnalyticsEvent(eventName: "event_\(index)")
            )
        }

        let apiClient = AnalyticsAPIClient(
            baseURL: configuration.baseURL
        )

        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: apiClient
        )

        let firstSelection = await manager.reserveBatches()

        #expect(firstSelection.count == 2)
        #expect(firstSelection.flatMap { $0 }.count == 10)

        let secondSelection = await manager.reserveBatches()

        #expect(secondSelection.isEmpty)

        let firstIDs = firstSelection
            .flatMap { $0 }
            .map { $0.event.id }

        #expect(Set(firstIDs).count == 10)
    }

    @Test("Released events can be selected again")
    func testReleasedEventsCanBeSelectedAgain() async throws {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        for index in 0..<10 {
            try await queue.enqueue(
                AnalyticsEvent(eventName: "event_\(index)")
            )
        }

        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(
                baseURL: configuration.baseURL
            )
        )

        let batches = await manager.reserveBatches()

        #expect(batches.count == 2)

        await manager.releaseBatch(batches[0])

        let nextSelection = await manager.reserveBatches()

        #expect(nextSelection.count == 1)

        let releasedIDs = batches[0].map { $0.event.id }
        let selectedIDs = nextSelection[0].map { $0.event.id }

        #expect(selectedIDs == releasedIDs)
    }

    @Test("Select next FIFO batch after releasing a slot")
    func testSelectNextBatchAfterRelease() async throws {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        for index in 0..<20 {
            try await queue.enqueue(
                AnalyticsEvent(eventName: "event_\(index)")
            )
        }

        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(
                baseURL: configuration.baseURL
            )
        )

        let initialBatches = await manager.reserveBatches()

        #expect(initialBatches.count == 2)

        let noAvailableSlots = await manager.reserveBatches()

        #expect(noAvailableSlots.isEmpty)

        // Simulate successful backend confirmation.
        let acceptedIDs = Set(
            initialBatches[0].map { $0.event.id }
        )

        // Remove successfully delivered events from the queue.
        try await queue.remove(ids: acceptedIDs)

        // Release the completed request.
        await manager.releaseBatch(initialBatches[0])

        let nextBatches = await manager.reserveBatches()

        #expect(nextBatches.count == 1)

        let names = nextBatches[0].map {
            $0.event.eventName
        }

        #expect(
            names == (10..<15).map { "event_\($0)" }
        )
    }
}
