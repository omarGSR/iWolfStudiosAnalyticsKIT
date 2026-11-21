//
//  AnalyticsBatchResponseProcessorTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//


import Foundation
import Testing
@testable import iWolfAnalyticsKIT

@Suite("Analytics Batch Response Processor")
struct AnalyticsBatchResponseProcessorTests {

    private func makeBatch(
        count: Int
    ) -> [QueuedAnalyticsEvent] {

        (0..<count).map { index in
            QueuedAnalyticsEvent(
                event: AnalyticsEvent(
                    eventName: "test_event_\(index)"
                )
            )
        }
    }

    private func makeResponse(
        rejections: [AnalyticsRejectedEvent]
    ) -> AnalyticsAPIResponse {

        AnalyticsAPIResponse(
            data: AnalyticsBatchResponse(
                rejected: rejections
            )
        )
    }

    @Test("Accepted events are removed")
    func acceptedEvents() throws {

        let batch = makeBatch(count: 3)
        let response = makeResponse(rejections: [])

        let result = try #require(
            AnalyticsBatchResponseProcessor.process(
                batch: batch,
                response: response
            )
        )

        #expect(result.removeIDs.count == 3)
        #expect(result.retryIDs.isEmpty)
        #expect(result.keepIDs.isEmpty)
    }

    @Test("Permanent rejection removes event")
    func permanentRejection() throws {

        let batch = makeBatch(count: 2)

        let response = makeResponse(
            rejections: [
                AnalyticsRejectedEvent(
                    index: 0,
                    eventUUID: batch[0].event.id,
                    code: "invalid_event_name"
                )
            ]
        )

        let result = try #require(
            AnalyticsBatchResponseProcessor.process(
                batch: batch,
                response: response
            )
        )

        #expect(result.removeIDs.count == 2)
        #expect(result.retryIDs.isEmpty)
    }

    @Test("Unknown rejection removes event")
    func unknownRejection() throws {

        let batch = makeBatch(count: 1)

        let response = makeResponse(
            rejections: [
                AnalyticsRejectedEvent(
                    index: 0,
                    eventUUID: batch[0].event.id,
                    code: "future_backend_error"
                )
            ]
        )

        let result = try #require(
            AnalyticsBatchResponseProcessor.process(
                batch: batch,
                response: response
            )
        )

        #expect(
            result.removeIDs == Set([batch[0].event.id])
        )
    }

    @Test("Temporary rejection retries event")
    func temporaryRejection() throws {

        let batch = makeBatch(count: 2)

        let response = makeResponse(
            rejections: [
                AnalyticsRejectedEvent(
                    index: 0,
                    eventUUID: batch[0].event.id,
                    code: "internal_error"
                )
            ]
        )

        let result = try #require(
            AnalyticsBatchResponseProcessor.process(
                batch: batch,
                response: response
            )
        )

        #expect(
            result.retryIDs == Set([batch[0].event.id])
        )

        #expect(
            result.removeIDs == Set([batch[1].event.id])
        )
    }

    @Test("Mismatched UUID invalidates response")
    func mismatchedUUID() {

        let batch = makeBatch(count: 1)

        let response = makeResponse(
            rejections: [
                AnalyticsRejectedEvent(
                    index: 0,
                    eventUUID: UUID(),
                    code: "invalid_event_name"
                )
            ]
        )

        let result = AnalyticsBatchResponseProcessor.process(
            batch: batch,
            response: response
        )

        #expect(result == nil)
    }

    @Test("Duplicate rejection invalidates response")
    func duplicateRejection() {

        let batch = makeBatch(count: 1)

        let rejection = AnalyticsRejectedEvent(
            index: 0,
            eventUUID: batch[0].event.id,
            code: "invalid_event_name"
        )

        let response = makeResponse(
            rejections: [rejection, rejection]
        )

        let result = AnalyticsBatchResponseProcessor.process(
            batch: batch,
            response: response
        )

        #expect(result == nil)
    }

    @Test("Out of range index invalidates response")
    func invalidIndex() {

        let batch = makeBatch(count: 1)

        let response = makeResponse(
            rejections: [
                AnalyticsRejectedEvent(
                    index: 10,
                    eventUUID: batch[0].event.id,
                    code: "invalid_event_name"
                )
            ]
        )

        let result = AnalyticsBatchResponseProcessor.process(
            batch: batch,
            response: response
        )

        #expect(result == nil)
    }
}
