//
//  AnalyticsSyncStateTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//


import Foundation
import Testing
@testable import iWolfAnalyticsKIT

@Suite("Analytics Sync State")
struct AnalyticsSyncStateTests {

    @Test("Initial state allows synchronization")
    func initialState() {

        let state = AnalyticsSyncState(batchSize: 20)

        #expect(state.effectiveBatchSize == 20)
        #expect(state.consecutiveFailures == 0)
        #expect(state.nextRetryAt == nil)
        #expect(state.canSync())
    }

    @Test("Temporary failures apply exponential backoff")
    func exponentialBackoff() throws {

        var state = AnalyticsSyncState(batchSize: 20)
        let now = Date(timeIntervalSince1970: 1_000)

        state.apply(.retry, at: now)

        #expect(state.consecutiveFailures == 1)
        #expect(state.nextRetryAt == now.addingTimeInterval(30))
        #expect(!state.canSync(at: now.addingTimeInterval(29)))
        #expect(state.canSync(at: now.addingTimeInterval(30)))

        state.apply(.retry, at: now.addingTimeInterval(30))

        #expect(state.consecutiveFailures == 2)
        #expect(
            state.nextRetryAt ==
            now.addingTimeInterval(90)
        )
    }

    @Test("Backoff is capped at fifteen minutes")
    func maximumBackoff() {

        var state = AnalyticsSyncState(batchSize: 20)
        let now = Date(timeIntervalSince1970: 1_000)

        for _ in 0..<10 {
            state.apply(.retry, at: now)
        }

        #expect(
            state.nextRetryAt ==
            now.addingTimeInterval(900)
        )
    }

    @Test("Oversized batches reduce effective batch size")
    func reduceBatchSize() {

        var state = AnalyticsSyncState(batchSize: 20)

        state.apply(.reduceBatchSize)

        #expect(state.effectiveBatchSize == 10)

        state.apply(.reduceBatchSize)

        #expect(state.effectiveBatchSize == 5)
    }

    @Test("Effective batch size never drops below one")
    func minimumBatchSize() {

        var state = AnalyticsSyncState(batchSize: 2)

        state.apply(.reduceBatchSize)
        state.apply(.reduceBatchSize)
        state.apply(.reduceBatchSize)

        #expect(state.effectiveBatchSize == 1)
    }

    @Test("Permanent errors stop automatic synchronization")
    func permanentError() {

        var state = AnalyticsSyncState(batchSize: 20)

        state.apply(.stop)

        #expect(state.isStopped)
        #expect(!state.canSync())
    }

    @Test("Successful synchronization clears backoff")
    func successfulSync() {

        var state = AnalyticsSyncState(batchSize: 20)

        state.apply(.retry)
        state.recordSuccess()

        #expect(state.consecutiveFailures == 0)
        #expect(state.nextRetryAt == nil)
        #expect(state.canSync())
    }

    @Test("Resume clears stopped state")
    func resume() {

        var state = AnalyticsSyncState(batchSize: 20)

        state.apply(.stop)
        state.resume()

        #expect(!state.isStopped)
        #expect(state.canSync())
    }

    @Test("Batch size can be restored")
    func resetBatchSize() {

        var state = AnalyticsSyncState(batchSize: 20)

        state.apply(.reduceBatchSize)
        state.resetBatchSize()

        #expect(state.effectiveBatchSize == 20)
    }
}
