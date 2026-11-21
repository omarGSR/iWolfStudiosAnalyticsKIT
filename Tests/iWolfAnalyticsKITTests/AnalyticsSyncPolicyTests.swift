//
//  AnalyticsSyncPolicyTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

@Suite("Analytics Sync Policy")
struct AnalyticsSyncPolicyTests {

    private let policy = AnalyticsSyncPolicy()

    @Test("Empty queue never triggers sync")
    func emptyQueue() {
        #expect(!policy.shouldSync(
            pendingEvents: 0,
            effectiveBatchSize: 20,
            oldestPendingAge: 1000,
            canSync: true
        ))
    }

    @Test("Full batch triggers immediate sync")
    func fullBatch() {
        #expect(policy.shouldSync(
            pendingEvents: 20,
            effectiveBatchSize: 20,
            oldestPendingAge: 0,
            canSync: true
        ))
    }

    @Test("Custom batch size is respected")
    func customBatchSize() {
        #expect(policy.shouldSync(
            pendingEvents: 30,
            effectiveBatchSize: 30,
            oldestPendingAge: 0,
            canSync: true
        ))
    }

    @Test("Reduced batch size triggers immediate sync")
    func reducedBatchSize() {
        #expect(policy.shouldSync(
            pendingEvents: 10,
            effectiveBatchSize: 10,
            oldestPendingAge: 0,
            canSync: true
        ))
    }

    @Test("Three events wait for normal interval")
    func minimumEvents() {
        #expect(!policy.shouldSync(
            pendingEvents: 3,
            effectiveBatchSize: 20,
            oldestPendingAge: 179,
            canSync: true
        ))

        #expect(policy.shouldSync(
            pendingEvents: 3,
            effectiveBatchSize: 20,
            oldestPendingAge: 180,
            canSync: true
        ))
    }

    @Test("One event is forced after fifteen minutes")
    func oneEventForcedSync() {
        #expect(!policy.shouldSync(
            pendingEvents: 1,
            effectiveBatchSize: 20,
            oldestPendingAge: 899,
            canSync: true
        ))

        #expect(policy.shouldSync(
            pendingEvents: 1,
            effectiveBatchSize: 20,
            oldestPendingAge: 900,
            canSync: true
        ))
    }

    @Test("Two events are forced after fifteen minutes")
    func twoEventsForcedSync() {
        #expect(policy.shouldSync(
            pendingEvents: 2,
            effectiveBatchSize: 20,
            oldestPendingAge: 900,
            canSync: true
        ))
    }

    @Test("Backoff prevents automatic sync")
    func backoffPreventsSync() {
        #expect(!policy.shouldSync(
            pendingEvents: 20,
            effectiveBatchSize: 20,
            oldestPendingAge: 1000,
            canSync: false
        ))
    }

    @Test("Custom intervals are respected")
    func customIntervals() {
        let customPolicy = AnalyticsSyncPolicy(
            syncInterval: 60,
            minEventsToSync: 5,
            forcedSyncInterval: 300
        )

        #expect(customPolicy.shouldSync(
            pendingEvents: 5,
            effectiveBatchSize: 20,
            oldestPendingAge: 60,
            canSync: true
        ))

        #expect(!customPolicy.shouldSync(
            pendingEvents: 2,
            effectiveBatchSize: 20,
            oldestPendingAge: 299,
            canSync: true
        ))

        #expect(customPolicy.shouldSync(
            pendingEvents: 2,
            effectiveBatchSize: 20,
            oldestPendingAge: 300,
            canSync: true
        ))
    }
}
