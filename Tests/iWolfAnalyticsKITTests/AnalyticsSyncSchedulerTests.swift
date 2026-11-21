//
//  AnalyticsSyncSchedulerTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Analytics Sync Scheduler", .serialized)
struct AnalyticsSyncSchedulerTests {

    // MARK: - Empty Queue

    @Test("Empty queue does not trigger synchronization")
    func emptyQueue() async throws {

        let context = try makeContext()
        defer { context.cleanup() }

        await context.scheduler.start()

        try await Task.sleep(for: .milliseconds(150))

        #expect(SchedulerMockURLProtocol.requestCount == 0)

        await context.scheduler.stop()
    }

    // MARK: - Full Batch

    @Test("Full batch triggers immediate synchronization")
    func fullBatch() async throws {

        let context = try makeContext(batchSize: 3)
        defer { context.cleanup() }

        for index in 0..<3 {
            try await context.queue.enqueue(
                AnalyticsEvent(eventName: "event_\(index)")
            )
        }

        await context.scheduler.start()

        let completed = await waitUntil {
            await context.queue.count() == 0
        }

        #expect(completed)
        #expect(SchedulerMockURLProtocol.requestCount == 1)

        await context.scheduler.stop()
    }

    // MARK: - Small Queue

    @Test("Small queue waits for the configured interval")
    func smallQueue() async throws {

        let context = try makeContext(
            batchSize: 10,
            syncInterval: 0.3,
            minEventsToSync: 3,
            forcedSyncInterval: 1
        )
        defer { context.cleanup() }

        for index in 0..<3 {
            try await context.queue.enqueue(
                AnalyticsEvent(eventName: "event_\(index)")
            )
        }

        await context.scheduler.start()

        #expect(SchedulerMockURLProtocol.requestCount == 0)

        let completed = await waitUntil {
            await context.queue.count() == 0
        }

        #expect(completed)
        #expect(SchedulerMockURLProtocol.requestCount == 1)

        await context.scheduler.stop()
    }

    // MARK: - Stop

    @Test("Stop cancels scheduled synchronization")
    func stopCancelsScheduledSync() async throws {

        let context = try makeContext(
            batchSize: 10,
            syncInterval: 0.3,
            minEventsToSync: 3,
            forcedSyncInterval: 1
        )
        defer { context.cleanup() }

        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "pending")
        )

        await context.scheduler.start()
        await context.scheduler.stop()

        try await Task.sleep(for: .seconds(1.2))

        #expect(SchedulerMockURLProtocol.requestCount == 0)
        #expect(await context.queue.count() == 1)
    }

    // MARK: - Concurrency and Error Handling

    @Test("Stop and restart during an active request preserves pending events")
    func stopAndRestartDuringSync() async throws {
        let context = try makeContext(batchSize: 1)
        defer { context.cleanup() }

        SchedulerMockURLProtocol.configure(
            mode: .accepted
        )

        SchedulerMockURLProtocol.holdResponses()

        // Enqueue the first event.
        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "first")
        )

        // Start the first synchronization.
        let firstStart = Task {
            await context.scheduler.start()
        }

        // Wait until the first HTTP request starts.
        let requestStarted = await waitUntil {
            SchedulerMockURLProtocol.requestCount == 1
        }

        #expect(requestStarted)

        // The first HTTP request is still pending.
        #expect(
            SchedulerMockURLProtocol.maximumConcurrentRequests == 1
        )

        #expect(await context.queue.count() == 1)

        // Stop the scheduler while HTTP is pending.
        await context.scheduler.stop()

        // Enqueue another event.
        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "second")
        )

        // Restart while the first HTTP request is still pending.
        let restartTask = Task {
            await context.scheduler.start()
        }

        // Give the restarted scheduler an opportunity to evaluate.
        try await Task.sleep(for: .milliseconds(100))

        // The manager must prevent overlapping HTTP requests.
        #expect(
            SchedulerMockURLProtocol.maximumConcurrentRequests == 1
        )

        // Release the first HTTP response.
        SchedulerMockURLProtocol.releasePendingResponses()

        // Wait for both scheduler evaluations.
        await firstStart.value
        await restartTask.value

        // All pending events must eventually be synchronized.
        let completed = await waitUntil(timeout: 4) {
            await context.queue.count() == 0
        }

        #expect(completed)

        // Both events must have been sent.
        #expect(
            SchedulerMockURLProtocol.requestCount >= 2
        )

        // No overlapping HTTP requests should have occurred.
        #expect(
            SchedulerMockURLProtocol.maximumConcurrentRequests == 1
        )

        await context.scheduler.stop()
    }
    
    @Test("Enqueuing during sync does not overlap HTTP requests")
    func eventEnqueuedDuringSync() async throws {

        let context = try makeContext(batchSize: 1)
        defer { context.cleanup() }

        SchedulerMockURLProtocol.configure(
            mode: .accepted,
            delay: 0.4
        )

        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "first")
        )

        let startTask = Task {
            await context.scheduler.start()
        }

        let started = await waitUntil {
            SchedulerMockURLProtocol.requestCount == 1
        }

        #expect(started)

        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "second")
        )

        await context.scheduler.eventEnqueued()

        let completed = await waitUntil(timeout: 4) {
            await context.queue.count() == 0
        }

        #expect(completed)

        #expect(
            SchedulerMockURLProtocol.requestCount >= 2
        )

        #expect(
            SchedulerMockURLProtocol.maximumConcurrentRequests == 1
        )

        await startTask.value
        await context.scheduler.stop()
    }

    @Test("HTTP 503 activates backoff without an immediate retry")
    func serverErrorRespectsBackoff() async throws {

        let context = try makeContext(batchSize: 1)
        defer { context.cleanup() }

        SchedulerMockURLProtocol.configure(
            mode: .serverError
        )

        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "server_error")
        )

        await context.scheduler.start()

        let received = await waitUntil {
            SchedulerMockURLProtocol.requestCount == 1
        }

        #expect(received)

        let backedOff = await waitUntil {
            let state = await context.manager.synchronizationState()
            return state.consecutiveFailures == 1
        }

        #expect(backedOff)

        try await Task.sleep(
            for: .milliseconds(300)
        )

        #expect(
            SchedulerMockURLProtocol.requestCount == 1
        )

        #expect(
            await context.queue.count() == 1
        )

        let state = await context.manager.synchronizationState()

        #expect(state.nextRetryAt != nil)
        #expect(!state.canSync())

        await context.scheduler.stop()
    }

    @Test("Kept event remains queued without rapid repeated requests")
    func keptEventDoesNotLoop() async throws {

        let context = try makeContext(
            batchSize: 1,
            syncInterval: 1
        )

        defer { context.cleanup() }

        SchedulerMockURLProtocol.configure(
            mode: .keep
        )

        let event = AnalyticsEvent(
            eventName: "configuration_error"
        )

        try await context.queue.enqueue(event)

        await context.scheduler.start()

        let received = await waitUntil {
            SchedulerMockURLProtocol.requestCount == 1
        }

        #expect(received)

        try await Task.sleep(
            for: .milliseconds(350)
        )

        let pending = await context.queue.peek(limit: 10)

        #expect(pending.count == 1)
        #expect(pending.first?.event.id == event.id)
        #expect(pending.first?.retryCount == 0)

        #expect(
            SchedulerMockURLProtocol.requestCount == 1
        )

        await context.scheduler.stop()
    }

    @Test("Permanent global error stops automatic synchronization")
    func permanentErrorStopsAutomaticSync() async throws {
        let context = try makeContext(batchSize: 1)
        defer { context.cleanup() }

        SchedulerMockURLProtocol.configure(mode: .invalidAppKey)

        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "invalid_app_key")
        )

        await context.scheduler.start()

        let stopped = await waitUntil {
            let state = await context.manager.synchronizationState()
            let count = await context.queue.count()
            return state.isStopped && count == 0
        }

        #expect(stopped)
        #expect(SchedulerMockURLProtocol.requestCount == 1)

        // A newly queued event must not trigger another HTTP request.
        try await context.queue.enqueue(
            AnalyticsEvent(eventName: "after_stop")
        )
        await context.scheduler.eventEnqueued()
        await context.scheduler.applicationDidBecomeActive()

        try await Task.sleep(for: .milliseconds(250))

        #expect(SchedulerMockURLProtocol.requestCount == 1)
        #expect(await context.queue.count() == 1)

        // Restarting only the scheduler must not resume a stopped manager.
        await context.scheduler.stop()
        await context.scheduler.start()

        try await Task.sleep(for: .milliseconds(250))

        #expect(SchedulerMockURLProtocol.requestCount == 1)
        #expect(await context.queue.count() == 1)

        await context.scheduler.stop()
    }

    // MARK: - Helpers

    private func makeContext(
        batchSize: Int = 3,
        syncInterval: TimeInterval = 0.3,
        minEventsToSync: Int = 3,
        forcedSyncInterval: TimeInterval = 1
    ) throws -> TestContext {

        SchedulerMockURLProtocol.reset()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SchedulerTests-\(UUID().uuidString)",
                isDirectory: true
            )

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let sessionConfiguration =
            URLSessionConfiguration.ephemeral

        sessionConfiguration.protocolClasses = [
            SchedulerMockURLProtocol.self
        ]

        let session = URLSession(
            configuration: sessionConfiguration
        )

        let baseURL = URL(
            string: "https://analytics.example.test/"
        )!

        let configuration = AnalyticsConfiguration(
            baseURL: baseURL,
            appKey: "awakenest",
            batchSize: batchSize,
            maxRetries: 4,
            maxSimultaneousRequests: 1
        )

        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(
                baseURL: baseURL,
                session: session
            )
        )

        let policy = AnalyticsSyncPolicy(
            syncInterval: syncInterval,
            minEventsToSync: minEventsToSync,
            forcedSyncInterval: forcedSyncInterval
        )

        let scheduler = AnalyticsSyncScheduler(
            queue: queue,
            syncManager: manager,
            policy: policy
        )

        return TestContext(
            directory: directory,
            queue: queue,
            scheduler: scheduler,
            manager: manager,
            session: session
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: () async -> Bool
    ) async -> Bool {

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {

            if await condition() {
                return true
            }

            try? await Task.sleep(
                for: .milliseconds(20)
            )
        }

        return await condition()
    }

    private struct TestContext {

        let directory: URL
        let queue: AnalyticsEventQueue
        let scheduler: AnalyticsSyncScheduler
        let manager: AnalyticsSyncManager
        let session: URLSession

        func cleanup() {
            session.invalidateAndCancel()

            try? FileManager.default.removeItem(
                at: directory
            )

            SchedulerMockURLProtocol.reset()
        }
    }
}

// MARK: - Mock HTTP Server

private final class SchedulerMockURLProtocol: URLProtocol,
                                                @unchecked Sendable {

    enum Mode: Sendable {
        case accepted
        case serverError
        case invalidAppKey
        case keep
    }

    private final class Storage: @unchecked Sendable {

        let lock = NSLock()

        var requestCount = 0
        var activeRequests = 0
        var maximumConcurrentRequests = 0
        var pendingResponses: [@Sendable () -> Void] = []

        var mode: Mode = .accepted
        var delay: TimeInterval = 0
    }

    private static let storage = Storage()

    private let stateLock = NSLock()
    private var cancelled = false
    private var finished = false

    static var requestCount: Int {
        storage.lock.withLock {
            storage.requestCount
        }
    }

    static var maximumConcurrentRequests: Int {
        storage.lock.withLock {
            storage.maximumConcurrentRequests
        }
    }

    static func configure(
        mode: Mode,
        delay: TimeInterval = 0
    ) {
        storage.lock.withLock {
            storage.mode = mode
            storage.delay = delay
        }
    }

    static func reset() {
        storage.lock.withLock {
            storage.requestCount = 0
            storage.activeRequests = 0
            storage.maximumConcurrentRequests = 0
            storage.mode = .accepted
            storage.delay = 0
            storage.pendingResponses.removeAll()
        }
    }
    
    static func holdResponses() {
        storage.lock.withLock {
            storage.delay = -1
        }
    }

    static func releasePendingResponses() {
        let responses = storage.lock.withLock {
            let pending = storage.pendingResponses
            storage.pendingResponses.removeAll()
            storage.delay = 0
            return pending
        }

        for response in responses {
            response()
        }
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {

        let (mode, delay) = Self.storage.lock.withLock {
            () -> (Mode, TimeInterval) in

            Self.storage.requestCount += 1
            Self.storage.activeRequests += 1

            Self.storage.maximumConcurrentRequests = max(
                Self.storage.maximumConcurrentRequests,
                Self.storage.activeRequests
            )

            return (
                Self.storage.mode,
                Self.storage.delay
            )
        }

        let deliver: @Sendable () -> Void = { [weak self] in
            self?.deliver(mode: mode)
        }

        if delay < 0 {
            Self.storage.lock.withLock {
                Self.storage.pendingResponses.append(deliver)
            }
        } else if delay > 0 {
            DispatchQueue.global().asyncAfter(
                deadline: .now() + delay,
                execute: deliver
            )
        } else {
            deliver()
        }
    }

    private func deliver(mode: Mode) {

        let shouldDeliver = stateLock.withLock {
            () -> Bool in

            guard !finished else {
                return false
            }

            finished = true
            return !cancelled
        }

        Self.storage.lock.withLock {
            Self.storage.activeRequests -= 1
        }

        guard shouldDeliver,
              let url = request.url else {
            return
        }

        let statusCode: Int
        let body: String

        switch mode {

        case .accepted:

            statusCode = 200
            body = #"{"data":{"rejected":[]}}"#

        case .serverError:

            statusCode = 503

            body = """
            {
                "error": {
                    "code": "service_unavailable",
                    "message": "Unavailable"
                }
            }
            """

        case .invalidAppKey:

            statusCode = 400
            body = #"{"error":{"code":"invalid_app_key","message":"Invalid app key"}}"#

        case .keep:

            statusCode = 200

            guard let eventUUID = Self.firstEventUUID(
                in: request
            ) else {

                client?.urlProtocol(
                    self,
                    didFailWithError: URLError(
                        .cannotParseResponse
                    )
                )

                return
            }

            body = """
            {
                "data": {
                    "rejected": [
                        {
                            "index": 0,
                            "event_uuid": "\(eventUUID)",
                            "code": "invalid_app_key"
                        }
                    ]
                }
            }
            """
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json"
            ]
        ) else {
            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )

        client?.urlProtocol(
            self,
            didLoad: Data(body.utf8)
        )

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {

        stateLock.withLock {
            cancelled = true
        }
    }

    private static func firstEventUUID(
        in request: URLRequest
    ) -> String? {

        let body: Data

        if let httpBody = request.httpBody {

            body = httpBody

        } else if let stream = request.httpBodyStream {

            stream.open()
            defer { stream.close() }

            var data = Data()

            var buffer = [UInt8](
                repeating: 0,
                count: 4096
            )

            while stream.hasBytesAvailable {

                let count = stream.read(
                    &buffer,
                    maxLength: buffer.count
                )

                guard count > 0 else {
                    break
                }

                data.append(
                    contentsOf: buffer.prefix(count)
                )
            }

            body = data

        } else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(
            with: body
        ),
        let dictionary = json as? [String: Any],
        let events = dictionary["events"] as? [[String: Any]],
        let first = events.first else {
            return nil
        }

        return first["event_uuid"] as? String
    }
}

