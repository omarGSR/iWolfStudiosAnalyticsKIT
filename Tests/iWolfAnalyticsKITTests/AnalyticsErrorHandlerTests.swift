//
//  AnalyticsErrorHandlerTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsErrorHandlerTests {

    // MARK: - Global errors

    @Test("Network errors retry")
    func testNetworkError() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: nil,
            errorCode: nil
        )

        #expect(action == .retry)
    }

    @Test("Server errors retry")
    func testServerError() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: 503,
            errorCode: "service_unavailable"
        )

        #expect(action == .retry)
    }

    @Test("Rate limiting retries")
    func testRateLimit() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: 429,
            errorCode: "rate_limit_exceeded"
        )

        #expect(action == .retry)
    }

    @Test("Oversized batches are reduced")
    func testBatchTooLarge() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: 413,
            errorCode: "request_too_large"
        )

        #expect(action == .reduceBatchSize)
    }

    @Test("Invalid app key stops synchronization and clears queue")
    func testInvalidAppKey() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: 400,
            errorCode: "invalid_app_key"
        )

        #expect(action == .stopAndClear)
    }

    @Test("Unknown global errors preserve the queue")
    func testUnknownGlobalError() {
        let action = AnalyticsGlobalErrorHandler.handle(
            statusCode: 400,
            errorCode: "future_global_error"
        )

        #expect(action == .stop)
    }

    // MARK: - Individual event errors

    @Test("Invalid events are removed")
    func testInvalidEvent() {
        let action = AnalyticsEventErrorHandler.handle(
            errorCode: "invalid_session_uuid"
        )

        #expect(action == .remove)
    }

    @Test("Temporary event errors retry")
    func testTemporaryEventError() {
        let action = AnalyticsEventErrorHandler.handle(
            errorCode: "service_unavailable"
        )

        #expect(action == .retry)
    }

    @Test("Configuration errors preserve events")
    func testEventConfigurationError() {
        let action = AnalyticsEventErrorHandler.handle(
            errorCode: "invalid_app_key"
        )

        #expect(action == .keep)
    }

    @Test("Unknown event errors are removed")
    func testUnknownEventError() {
        let action = AnalyticsEventErrorHandler.handle(
            errorCode: "future_event_error"
        )

        #expect(action == .remove)
    }
}
