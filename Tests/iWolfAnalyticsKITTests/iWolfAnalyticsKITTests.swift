//
//  iWolfAnalyticsKITTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

@Suite("iWolf Analytics KIT")
struct iWolfAnalyticsKITTests {

    private func makeConfiguration() -> AnalyticsConfiguration {
        AnalyticsConfiguration(
            baseURL: URL(string: "https://example.com/api/v1")!,
            appKey: "io.iwolfstudios.AwakeNest.debug"
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

        // Both callers have completed successfully.
        // The SDK must be ready for tracking.
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
    }

}
