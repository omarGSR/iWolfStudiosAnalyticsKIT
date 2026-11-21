//
//  AnalyticsSyncManagerTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Analytics Sync Manager", .serialized)
struct AnalyticsSyncManagerTests {

    // MARK: - Batch Management (existing tests)

    @Test("Sync completes with an empty queue")
    func testSyncWithEmptyQueue() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest"
        )
        let queue = try AnalyticsEventQueue(directoryURL: directory)
        let apiClient = AnalyticsAPIClient(baseURL: configuration.baseURL)
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
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )
        let queue = try AnalyticsEventQueue(directoryURL: directory)
        for index in 0..<10 {
            try await queue.enqueue(AnalyticsEvent(eventName: "event_\(index)"))
        }
        let apiClient = AnalyticsAPIClient(baseURL: configuration.baseURL)
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

        let firstIDs = firstSelection.flatMap { $0 }.map { $0.event.id }
        #expect(Set(firstIDs).count == 10)
    }

    @Test("Released events can be selected again")
    func testReleasedEventsCanBeSelectedAgain() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )
        let queue = try AnalyticsEventQueue(directoryURL: directory)
        for index in 0..<10 {
            try await queue.enqueue(AnalyticsEvent(eventName: "event_\(index)"))
        }
        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(baseURL: configuration.baseURL)
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
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.com")!,
            appKey: "awakenest",
            batchSize: 5,
            maxSimultaneousRequests: 2
        )
        let queue = try AnalyticsEventQueue(directoryURL: directory)
        for index in 0..<20 {
            try await queue.enqueue(AnalyticsEvent(eventName: "event_\(index)"))
        }
        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(baseURL: configuration.baseURL)
        )

        let initialBatches = await manager.reserveBatches()
        #expect(initialBatches.count == 2)
        let noAvailableSlots = await manager.reserveBatches()
        #expect(noAvailableSlots.isEmpty)

        let acceptedIDs = Set(initialBatches[0].map { $0.event.id })
        try await queue.remove(ids: acceptedIDs)
        await manager.releaseBatch(initialBatches[0])

        let nextBatches = await manager.reserveBatches()
        #expect(nextBatches.count == 1)
        let names = nextBatches[0].map { $0.event.eventName }
        #expect(names == (10..<15).map { "event_\($0)" })
    }

    // MARK: - HTTP Responses

    @Test("HTTP 200 removes accepted events")
    func testHTTP200() async throws {
        let context = try makeContext(responses: ["accepted": .accepted])
        defer { context.cleanup() }
        try await context.queue.enqueue(AnalyticsEvent(eventName: "accepted"))

        await context.manager.sync()

        #expect(await context.queue.count() == 0)
        #expect(MockAnalyticsURLProtocol.requestCount == 1)
    }

    @Test("HTTP 503 preserves events and activates backoff")
    func testHTTP503() async throws {
        let context = try makeContext(responses: ["server_error": .serverError])
        defer { context.cleanup() }
        let event = AnalyticsEvent(eventName: "server_error")
        try await context.queue.enqueue(event)

        await context.manager.sync()
        let queued = await context.queue.peek(limit: 10)
        let state = await context.manager.synchronizationState()

        #expect(queued.count == 1)
        #expect(queued.first?.event.id == event.id)
        #expect(queued.first?.retryCount == 0)
        #expect(state.consecutiveFailures == 1)
        #expect(!state.canSync())

        await context.manager.sync()
        #expect(MockAnalyticsURLProtocol.requestCount == 1)
    }

    @Test("HTTP 401 stops synchronization")
    func testHTTP401() async throws {
        let context = try makeContext(responses: ["unauthorized": .unauthorized])
        defer { context.cleanup() }
        try await context.queue.enqueue(AnalyticsEvent(eventName: "unauthorized"))

        await context.manager.sync()
        let state = await context.manager.synchronizationState()
        let queued = await context.queue.peek(limit: 10)

        #expect(state.isStopped)
        #expect(queued.count == 1)
        #expect(queued.first?.retryCount == 0)

        await context.manager.sync()
        #expect(MockAnalyticsURLProtocol.requestCount == 1)
    }

    @Test("HTTP 413 reduces effective batch size")
    func testHTTP413() async throws {
        let context = try makeContext(
            responses: ["oversized": .tooLarge],
            batchSize: 4,
            maxSimultaneousRequests: 1
        )
        defer { context.cleanup() }
        for _ in 0..<4 {
            try await context.queue.enqueue(AnalyticsEvent(eventName: "oversized"))
        }

        await context.manager.sync()
        let state = await context.manager.synchronizationState()
        let queued = await context.queue.peek(limit: 10)

        #expect(state.effectiveBatchSize == 2)
        #expect(queued.count == 4)
        #expect(queued.allSatisfy { $0.retryCount == 0 })
        #expect(!state.canSync())
    }

    // MARK: - Concurrent Requests

    @Test("HTTP 200 and 503 preserve global backoff")
    func testConcurrentSuccessAndRetry() async throws {
        let context = try makeContext(responses: [
            "accepted": .accepted,
            "server_error": .serverError
        ])
        defer { context.cleanup() }
        try await enqueueTwoEvents("accepted", "server_error", in: context.queue)

        await context.manager.sync()
        let state = await context.manager.synchronizationState()
        let queued = await context.queue.peek(limit: 10)

        #expect(MockAnalyticsURLProtocol.requestCount == 2)
        #expect(queued.map { $0.event.eventName } == ["server_error"])
        #expect(queued.first?.retryCount == 0)
        #expect(state.consecutiveFailures == 1)
        #expect(!state.canSync())
    }

    @Test("HTTP 401 takes priority over HTTP 503")
    func testConcurrentStopPriority() async throws {
        let context = try makeContext(responses: [
            "unauthorized": .unauthorized,
            "server_error": .serverError
        ])
        defer { context.cleanup() }
        try await enqueueTwoEvents("unauthorized", "server_error", in: context.queue)

        await context.manager.sync()
        let state = await context.manager.synchronizationState()
        let queued = await context.queue.peek(limit: 10)

        #expect(MockAnalyticsURLProtocol.requestCount == 2)
        #expect(state.isStopped)
        #expect(queued.count == 2)
        #expect(queued.allSatisfy { $0.retryCount == 0 })
    }

    @Test("HTTP 413 takes priority over HTTP 503")
    func testConcurrentBatchReductionPriority() async throws {
        let context = try makeContext(responses: [
            "oversized": .tooLarge,
            "server_error": .serverError
        ])
        defer { context.cleanup() }
        try await enqueueTwoEvents("oversized", "server_error", in: context.queue)

        await context.manager.sync()
        let state = await context.manager.synchronizationState()
        let queued = await context.queue.peek(limit: 10)

        #expect(MockAnalyticsURLProtocol.requestCount == 2)
        #expect(state.effectiveBatchSize == 1)
        #expect(state.consecutiveFailures == 0)
        #expect(!state.isStopped)
        #expect(queued.count == 2)
        #expect(queued.allSatisfy { $0.retryCount == 0 })
    }

    // MARK: - Test Helpers

    private func enqueueTwoEvents(
        _ first: String,
        _ second: String,
        in queue: AnalyticsEventQueue
    ) async throws {
        try await queue.enqueue(AnalyticsEvent(eventName: first))
        try await queue.enqueue(AnalyticsEvent(eventName: second))
    }

    private func makeContext(
        responses: [String: MockAnalyticsResponse],
        batchSize: Int = 1,
        maxSimultaneousRequests: Int = 2
    ) throws -> TestContext {
        MockAnalyticsURLProtocol.configure(responses: responses)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsSyncManagerTests-\(UUID().uuidString)")
        let queue = try AnalyticsEventQueue(directoryURL: directory)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockAnalyticsURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        let configuration = AnalyticsConfiguration(
            baseURL: URL(string: "https://analytics.example.test")!,
            appKey: "awakenest",
            batchSize: batchSize,
            maxRetries: 4,
            maxSimultaneousRequests: maxSimultaneousRequests
        )
        let manager = AnalyticsSyncManager(
            configuration: configuration,
            queue: queue,
            apiClient: AnalyticsAPIClient(
                baseURL: configuration.baseURL,
                session: session
            )
        )

        return TestContext(
            directory: directory,
            queue: queue,
            manager: manager,
            session: session
        )
    }

    private struct TestContext {
        let directory: URL
        let queue: AnalyticsEventQueue
        let manager: AnalyticsSyncManager
        let session: URLSession

        func cleanup() {
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: directory)
            MockAnalyticsURLProtocol.reset()
        }
    }
}

// MARK: - Mock HTTP Server

private enum MockAnalyticsResponse: Sendable {
    case accepted
    case serverError
    case unauthorized
    case tooLarge

    var statusCode: Int {
        switch self {
        case .accepted: 200
        case .serverError: 503
        case .unauthorized: 401
        case .tooLarge: 413
        }
    }

    var body: String {
        switch self {
        case .accepted:
            return #"{"data":{"rejected":[]}}"#
        case .serverError:
            return #"{"error":{"code":"service_unavailable","message":"Unavailable"}}"#
        case .unauthorized:
            return #"{"error":{"code":"unauthorized","message":"Unauthorized"}}"#
        case .tooLarge:
            return #"{"error":{"code":"request_too_large","message":"Too large"}}"#
        }
    }
}

private final class MockAnalyticsURLProtocol: URLProtocol {

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var responses: [String: MockAnalyticsResponse] = [:]
        var requestCount = 0
    }

    private static let storage = Storage()

    static var requestCount: Int {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.requestCount
    }

    static func configure(responses: [String: MockAnalyticsResponse]) {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.responses = responses
        storage.requestCount = 0
    }

    static func reset() {
        configure(responses: [:])
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let eventName = Self.firstEventName(in: request)

        Self.storage.lock.lock()
        Self.storage.requestCount += 1
        let mockResponse = Self.storage.responses[eventName]
        Self.storage.lock.unlock()

        guard let mockResponse,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data(mockResponse.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}


    private static func firstEventName(in request: URLRequest) -> String {

        let body: Data

        if let httpBody = request.httpBody {
            body = httpBody

        } else if let stream = request.httpBodyStream {

            stream.open()
            defer { stream.close() }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)

            while stream.hasBytesAvailable {
                let count = stream.read(
                    &buffer,
                    maxLength: buffer.count
                )

                guard count > 0 else {
                    break
                }

                data.append(contentsOf: buffer.prefix(count))
            }

            body = data

        } else {
            return ""
        }

        guard let object = try? JSONSerialization.jsonObject(
            with: body
        ),
        let dictionary = object as? [String: Any],
        let events = dictionary["events"] as? [[String: Any]],
        let first = events.first,
        let eventName = first["event_name"] as? String else {
            return ""
        }

        return eventName
    }

}
