//
//  AnalyticsEventQueue.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Manages a persistent queue of analytics events.
public actor AnalyticsEventQueue {

    private let fileURL: URL
    private var events: [QueuedAnalyticsEvent]

    public init(directoryURL: URL? = nil) throws {

        let directory: URL

        if let directoryURL {
            directory = directoryURL
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let bundleIdentifier = Bundle.main.bundleIdentifier
                ?? "iWolfAnalytics"

            directory = applicationSupport
                .appendingPathComponent(
                    bundleIdentifier,
                    isDirectory: true
                )
                .appendingPathComponent(
                    "Analytics",
                    isDirectory: true
                )
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        self.fileURL = directory.appendingPathComponent(
            "events_queue.json"
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            self.events = try decoder.decode(
                [QueuedAnalyticsEvent].self,
                from: data
            )
        } else {
            self.events = []
        }
    }

    // MARK: - Enqueue

    /// Adds an event with an initial retry count of zero.
    public func enqueue(_ event: AnalyticsEvent) throws {

        let queuedEvent = QueuedAnalyticsEvent(
            event: event
        )

        var updatedEvents = events
        updatedEvents.append(queuedEvent)

        try persist(updatedEvents)
        events = updatedEvents
    }

    // MARK: - Peek

    /// Returns pending events with their retry information.
    func peek(limit: Int) -> [QueuedAnalyticsEvent] {
        Array(events.prefix(max(0, limit)))
    }
    
    /// Returns pending events excluding those already in flight.
    ///
    /// Preserves FIFO order and limits the number of returned events.
    func peek(
        limit: Int,
        excluding excludedIDs: Set<UUID>
    ) -> [QueuedAnalyticsEvent] {

        guard limit > 0 else {
            return []
        }

        var result: [QueuedAnalyticsEvent] = []
        var selectedIDs = Set<UUID>()

        for queuedEvent in events {

            let id = queuedEvent.event.id

            guard !excludedIDs.contains(id),
                  selectedIDs.insert(id).inserted else {
                continue
            }

            result.append(queuedEvent)

            if result.count == limit {
                break
            }
        }

        return result
    }

    // MARK: - Remove

    /// Removes events identified by their UUIDs.
    public func remove(ids: Set<UUID>) throws {

        guard !ids.isEmpty else {
            return
        }

        let updatedEvents = events.filter {
            !ids.contains($0.event.id)
        }

        try persist(updatedEvents)
        events = updatedEvents
    }

    // MARK: - Retry

    /// Increments the retry count of a specific event.
    func incrementRetryCount(for id: UUID) throws {

        guard let index = events.firstIndex(where: {
            $0.event.id == id
        }) else {
            return
        }

        var updatedEvents = events

        updatedEvents[index].incrementRetryCount()

        try persist(updatedEvents)
        events = updatedEvents
    }
    
    // MARK: - Oldest Event

    /// Returns the enqueue date of the oldest pending event.
    func oldestEnqueuedAt() -> Date? {
        events.first?.enqueuedAt
    }

    // MARK: - Count

    /// Returns the number of pending events.
    public func count() -> Int {
        events.count
    }
    
    
    // MARK: - Batch Response

    /// Applies individual event actions and persists the result
    /// in a single operation.
    ///
    /// Temporary rejections increment retryCount.
    /// Events reaching maxRetries are discarded.
    func apply(
        _ result: AnalyticsBatchProcessingResult,
        maxRetries: Int
    ) throws {

        let retryLimit = max(0, maxRetries)

        var updatedEvents: [QueuedAnalyticsEvent] = []

        for var queuedEvent in events {

            let id = queuedEvent.event.id

            // Accepted or permanently rejected.
            if result.removeIDs.contains(id) {
                continue
            }

            // Temporarily rejected.
            if result.retryIDs.contains(id) {

                queuedEvent.incrementRetryCount()

                if !queuedEvent.canRetry(
                    maxRetries: retryLimit
                ) {
                    continue
                }
            }

            // Keep all other events unchanged.
            updatedEvents.append(queuedEvent)
        }

        try persist(updatedEvents)
        events = updatedEvents
    }


    // MARK: - Persistence

    private func persist(_ events: [QueuedAnalyticsEvent]) throws {

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(events)

        try data.write(
            to: fileURL,
            options: .atomic
        )
    }
}
