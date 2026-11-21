//
//  AnalyticsEventQueueTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsEventQueueTests {

    @Test("Events persist between queue instances")
    func testPersistence() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let event = AnalyticsEvent(
            eventName: "session_started"
        )

        try await firstQueue.enqueue(event)

        let secondQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let events = await secondQueue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.id == event.id)
    }

    @Test("Events maintain insertion order")
    func testEventOrder() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let first = AnalyticsEvent(eventName: "session_started")
        let second = AnalyticsEvent(eventName: "history_opened")
        let third = AnalyticsEvent(eventName: "session_ended")

        try await queue.enqueue(first)
        try await queue.enqueue(second)
        try await queue.enqueue(third)

        let events = await queue.peek(limit: 2)

        #expect(events.map(\.event.id) == [first.id, second.id])
        #expect(await queue.count() == 3)
    }

    @Test("Removing acknowledged events preserves new events")
    func testRemoveAcknowledgedEvents() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let first = AnalyticsEvent(eventName: "session_started")
        let second = AnalyticsEvent(eventName: "history_opened")
        let third = AnalyticsEvent(eventName: "session_ended")

        try await queue.enqueue(first)
        try await queue.enqueue(second)

        // Simulate a batch being prepared.
        let batch = await queue.peek(limit: 2)

        // A new event arrives while the batch is being sent.
        try await queue.enqueue(third)

        // The backend acknowledges the original batch.
        try await queue.remove(
            ids: Set(batch.map(\.event.id))
        )

        let remaining = await queue.peek(limit: 10)

        #expect(remaining.count == 1)
        #expect(remaining.first?.event.id == third.id)
    }
    
    @Test("Retry count persists between queue instances")
    func testRetryCountPersistence() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let event = AnalyticsEvent(
            eventName: "session_started"
        )

        try await firstQueue.enqueue(event)

        try await firstQueue.incrementRetryCount(for: event.id)
        try await firstQueue.incrementRetryCount(for: event.id)

        let secondQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let queuedEvents = await secondQueue.peek(limit: 10)

        #expect(queuedEvents.count == 1)
        #expect(queuedEvents.first?.event.id == event.id)
        #expect(queuedEvents.first?.retryCount == 2)
    }

    
    // MARK: - Batch Response Processing

    @Test("Accepted and permanently rejected events are removed")
    func testApplyRemovesEvents() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(directoryURL: directory)

        let accepted = AnalyticsEvent(eventName: "app_open")
        let rejected = AnalyticsEvent(eventName: "invalid_event")
        let pending = AnalyticsEvent(eventName: "settings_opened")

        try await queue.enqueue(accepted)
        try await queue.enqueue(rejected)
        try await queue.enqueue(pending)

        let result = AnalyticsBatchProcessingResult(
            removeIDs: [accepted.id, rejected.id],
            retryIDs: [],
            keepIDs: []
        )

        try await queue.apply(result, maxRetries: 4)

        let events = await queue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.id == pending.id)
    }

    @Test("Temporary rejection increments retry count")
    func testApplyIncrementsRetryCount() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(directoryURL: directory)

        let event = AnalyticsEvent(eventName: "app_open")

        try await queue.enqueue(event)

        let result = AnalyticsBatchProcessingResult(
            removeIDs: [],
            retryIDs: [event.id],
            keepIDs: []
        )

        try await queue.apply(result, maxRetries: 4)

        let events = await queue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.retryCount == 1)
    }

    @Test("Event is removed when retry limit is reached")
    func testApplyRemovesExhaustedEvent() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(directoryURL: directory)

        let event = AnalyticsEvent(eventName: "app_open")

        try await queue.enqueue(event)

        let result = AnalyticsBatchProcessingResult(
            removeIDs: [],
            retryIDs: [event.id],
            keepIDs: []
        )

        for _ in 0..<4 {
            try await queue.apply(result, maxRetries: 4)
        }

        #expect(await queue.count() == 0)
    }

    @Test("Keep action preserves event without retries")
    func testApplyKeepsEvent() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let queue = try AnalyticsEventQueue(directoryURL: directory)

        let event = AnalyticsEvent(eventName: "app_open")

        try await queue.enqueue(event)

        let result = AnalyticsBatchProcessingResult(
            removeIDs: [],
            retryIDs: [],
            keepIDs: [event.id]
        )

        try await queue.apply(result, maxRetries: 4)

        let events = await queue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.id == event.id)
        #expect(events.first?.retryCount == 0)
    }

    @Test("Batch response changes persist between queue instances")
    func testApplyPersistence() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let accepted = AnalyticsEvent(eventName: "app_open")
        let retry = AnalyticsEvent(eventName: "settings_opened")

        try await firstQueue.enqueue(accepted)
        try await firstQueue.enqueue(retry)

        let result = AnalyticsBatchProcessingResult(
            removeIDs: [accepted.id],
            retryIDs: [retry.id],
            keepIDs: []
        )

        try await firstQueue.apply(result, maxRetries: 4)

        // Reconstruct the queue from its persisted file.
        let restoredQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let events = await restoredQueue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.id == retry.id)
        #expect(events.first?.retryCount == 1)
    }
    
    
    @Test("Enqueue date persists between queue instances")
    func testEnqueuedAtPersistence() async throws {

        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let event = AnalyticsEvent(eventName: "app_open")

        try await firstQueue.enqueue(event)

        let originalDate = await firstQueue.oldestEnqueuedAt()

        let restoredQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let restoredDate = await restoredQueue.oldestEnqueuedAt()

        #expect(originalDate != nil)
        #expect(restoredDate != nil)

        if let originalDate, let restoredDate {
            // JSON ISO8601 encoding has second-level precision.
            #expect(
                abs(originalDate.timeIntervalSince(restoredDate)) < 1
            )
        }
    }

    @Test("Old queue format remains compatible")
    func testLegacyQueueDecoding() throws {

        let event = AnalyticsEvent(eventName: "app_open")

        let legacyEvent = QueuedAnalyticsEvent(
            event: event,
            retryCount: 2
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let encoded = try encoder.encode(legacyEvent)

        // Simulate an older SDK that did not store enqueuedAt.
        var dictionary = try #require(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )

        dictionary.removeValue(forKey: "enqueuedAt")

        let legacyData = try JSONSerialization.data(
            withJSONObject: dictionary
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            QueuedAnalyticsEvent.self,
            from: legacyData
        )

        #expect(restored.event.id == event.id)
        #expect(restored.retryCount == 2)
        #expect(
            abs(
                restored.enqueuedAt.timeIntervalSince(event.occurredAt)
            ) < 1
        )
    }


    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "iWolfAnalyticsTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
