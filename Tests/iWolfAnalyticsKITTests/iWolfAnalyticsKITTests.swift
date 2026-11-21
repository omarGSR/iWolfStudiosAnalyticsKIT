//
//  iWolfAnalyticsKITTests.swift
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

@Suite("iWolf Analytics KIT", .serialized)
struct iWolfAnalyticsKITTests {

    // MARK: - Helpers

    private func makeConfiguration(
        batchSize: Int = 20
    ) -> AnalyticsConfiguration {

        AnalyticsConfiguration(
            baseURL: URL(
                string: "https://example.com/api/v1"
            )!,
            appKey: "io.iwolfstudios.AwakeNest.debug",
            batchSize: batchSize
        )
    }

    private func makeTemporaryDirectory() throws -> URL {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private func makeMockClient() -> (
        client: AnalyticsAPIClient,
        session: URLSession
    ) {

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            KITMockURLProtocol.self
        ]

        let session = URLSession(
            configuration: configuration
        )

        let client = AnalyticsAPIClient(
            baseURL: URL(
                string: "https://example.com/api/v1"
            )!,
            session: session
        )

        return (client, session)
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

    // MARK: - Existing Tests

    @Test("Configuration registers one app_open event")
    func configurationRegistersAppOpen() async throws {

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let sdk = iWolfAnalyticsKIT(queue: queue)

        try await sdk.configure(makeConfiguration())

        let events = await queue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.eventName == "app_open")
        #expect(events.first?.retryCount == 0)

        await sdk.stopAutomaticSync()
    }

    @Test("Repeated configuration does not duplicate app_open")
    func repeatedConfiguration() async throws {

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let sdk = iWolfAnalyticsKIT(queue: queue)
        let configuration = makeConfiguration()

        try await sdk.configure(configuration)
        try await sdk.configure(configuration)

        let events = await queue.peek(limit: 10)

        #expect(events.count == 1)
        #expect(events.first?.event.eventName == "app_open")

        await sdk.stopAutomaticSync()
    }

    @Test("app_open survives queue reconstruction")
    func appOpenPersistence() async throws {

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let sdk = iWolfAnalyticsKIT(queue: queue)

        try await sdk.configure(makeConfiguration())

        let restoredQueue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let restoredEvents = await restoredQueue.peek(limit: 10)

        #expect(restoredEvents.count == 1)
        #expect(restoredEvents.first?.event.eventName == "app_open")

        await sdk.stopAutomaticSync()
    }

    @Test("Concurrent configuration shares initialization result")
    func concurrentConfiguration() async throws {

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let sdk = iWolfAnalyticsKIT(queue: queue)
        let configuration = makeConfiguration()

        async let first: Void = sdk.configure(configuration)
        async let second: Void = sdk.configure(configuration)

        try await first
        try await second

        try await sdk.track("settings_opened")

        let events = await queue.peek(limit: 10)

        #expect(events.count == 2)

        #expect(
            events.filter {
                $0.event.eventName == "app_open"
            }.count == 1
        )

        #expect(
            events.filter {
                $0.event.eventName == "settings_opened"
            }.count == 1
        )

        await sdk.stopAutomaticSync()
    }

    // MARK: - Scheduler Integration

    @Test("Repeated configuration does not duplicate automatic synchronization")
    func schedulerStartsOnce() async throws {

        KITMockURLProtocol.reset()

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            KITMockURLProtocol.reset()
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let mock = makeMockClient()
        defer { mock.session.invalidateAndCancel() }

        let sdk = iWolfAnalyticsKIT(
            queue: queue,
            apiClient: mock.client
        )

        // Batch includes app_open + two tracked events.
        let configuration = makeConfiguration(batchSize: 3)

        try await sdk.configure(configuration)
        try await sdk.configure(configuration)

        try await sdk.track("session_started")
        try await sdk.track("settings_opened")

        let completed = await waitUntil {
            await queue.count() == 0
        }

        #expect(completed)
        #expect(KITMockURLProtocol.requestCount == 1)

        await sdk.stopAutomaticSync()
    }

    @Test("Tracking a full batch triggers automatic synchronization")
    func trackingTriggersAutomaticSync() async throws {

        KITMockURLProtocol.reset()

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            KITMockURLProtocol.reset()
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let mock = makeMockClient()
        defer { mock.session.invalidateAndCancel() }

        let sdk = iWolfAnalyticsKIT(
            queue: queue,
            apiClient: mock.client
        )

        try await sdk.configure(
            makeConfiguration(batchSize: 3)
        )

        // app_open is already queued.
        #expect(await queue.count() == 1)
        #expect(KITMockURLProtocol.requestCount == 0)

        try await sdk.track("session_started")

        #expect(await queue.count() == 2)
        #expect(KITMockURLProtocol.requestCount == 0)

        try await sdk.track("session_ended")

        let completed = await waitUntil {
            await queue.count() == 0
        }

        #expect(completed)
        #expect(KITMockURLProtocol.requestCount == 1)

        await sdk.stopAutomaticSync()
    }

    @Test("Stopping automatic sync preserves events until restarted")
    func stopAndRestartAutomaticSync() async throws {

        KITMockURLProtocol.reset()

        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            KITMockURLProtocol.reset()
        }

        let queue = try AnalyticsEventQueue(
            directoryURL: directory
        )

        let mock = makeMockClient()
        defer { mock.session.invalidateAndCancel() }

        let sdk = iWolfAnalyticsKIT(
            queue: queue,
            apiClient: mock.client
        )

        try await sdk.configure(
            makeConfiguration(batchSize: 3)
        )

        await sdk.stopAutomaticSync()

        try await sdk.track("session_started")
        try await sdk.track("session_ended")

        try await Task.sleep(
            for: .milliseconds(200)
        )

        #expect(await queue.count() == 3)
        #expect(KITMockURLProtocol.requestCount == 0)

        await sdk.startAutomaticSync()

        let completed = await waitUntil {
            await queue.count() == 0
        }

        #expect(completed)
        #expect(KITMockURLProtocol.requestCount == 1)

        await sdk.stopAutomaticSync()
    }
}

// MARK: - Mock HTTP Server

private final class KITMockURLProtocol: URLProtocol {

    private final class Storage: @unchecked Sendable {

        let lock = NSLock()
        var requestCount = 0
    }

    private static let storage = Storage()

    static var requestCount: Int {
        storage.lock.withLock {
            storage.requestCount
        }
    }

    static func reset() {
        storage.lock.withLock {
            storage.requestCount = 0
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

        Self.storage.lock.withLock {
            Self.storage.requestCount += 1
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json"
                ]
              ) else {

            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        let body = #"{"data":{"rejected":[]}}"#

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

    override func stopLoading() {}
}
