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

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "iWolfAnalyticsTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
