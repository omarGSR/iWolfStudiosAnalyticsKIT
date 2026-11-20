//
//  AnalyticsBatchSelectorTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsBatchSelectorTests {

    private func makeEvents(
        count: Int
    ) -> [QueuedAnalyticsEvent] {

        (0..<count).map { index in
            QueuedAnalyticsEvent(
                event: AnalyticsEvent(
                    eventName: "event_\(index)"
                )
            )
        }
    }

    @Test("Select events in FIFO order")
    func testFIFOOrder() {

        let events = makeEvents(count: 10)

        let batches = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 4,
            maxBatches: 3
        )

        #expect(batches.count == 3)
        #expect(batches[0].count == 4)
        #expect(batches[1].count == 4)
        #expect(batches[2].count == 2)

        let selectedNames = batches
            .flatMap { $0 }
            .map { $0.event.eventName }

        let expectedNames = (0..<10).map { "event_\($0)" }

        #expect(selectedNames == expectedNames)
    }

    @Test("Respect maximum number of batches")
    func testMaximumBatches() {

        let events = makeEvents(count: 200)

        let batches = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 40,
            maxBatches: 2
        )

        #expect(batches.count == 2)
        #expect(batches.flatMap { $0 }.count == 80)

        #expect(
            batches[0].first?.event.eventName == "event_0"
        )

        #expect(
            batches[1].last?.event.eventName == "event_79"
        )
    }

    @Test("Exclude events already in flight")
    func testInFlightExclusion() {

        let events = makeEvents(count: 10)

        let inFlightIDs = Set(
            events.prefix(4).map { $0.event.id }
        )

        let batches = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 3,
            maxBatches: 2,
            excluding: inFlightIDs
        )

        let selectedIDs = batches
            .flatMap { $0 }
            .map { $0.event.id }

        #expect(selectedIDs.count == 6)

        #expect(
            selectedIDs.allSatisfy {
                !inFlightIDs.contains($0)
            }
        )

        #expect(
            batches[0].first?.event.eventName == "event_4"
        )
    }

    @Test("Do not select duplicate event UUIDs")
    func testDuplicateIDs() {

        let event = QueuedAnalyticsEvent(
            event: AnalyticsEvent(
                eventName: "session_started"
            )
        )

        let events = [event, event, event]

        let batches = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 2,
            maxBatches: 2
        )

        #expect(batches.count == 1)
        #expect(batches[0].count == 1)
        #expect(batches[0][0].event.id == event.event.id)
    }

    @Test("Return empty batches when queue is empty")
    func testEmptyQueue() {

        let batches = AnalyticsBatchSelector.select(
            from: [],
            batchSize: 20,
            maxBatches: 2
        )

        #expect(batches.isEmpty)
    }

    @Test("Reject invalid batch configuration")
    func testInvalidConfiguration() {

        let events = makeEvents(count: 10)

        let invalidBatchSize = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 0,
            maxBatches: 2
        )

        let invalidMaxBatches = AnalyticsBatchSelector.select(
            from: events,
            batchSize: 20,
            maxBatches: 0
        )

        #expect(invalidBatchSize.isEmpty)
        #expect(invalidMaxBatches.isEmpty)
    }
}
