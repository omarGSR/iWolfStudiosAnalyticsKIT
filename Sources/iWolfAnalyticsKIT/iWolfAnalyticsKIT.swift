// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation

/// Public entry point for iWolf Analytics.
public actor iWolfAnalyticsKIT {

    // MARK: - Singleton

    public static let shared = iWolfAnalyticsKIT()

    // MARK: - Dependencies

    private let injectedQueue: AnalyticsEventQueue?

    private var queue: AnalyticsEventQueue?
    private var syncManager: AnalyticsSyncManager?

    // MARK: - State

    private var isConfigured = false
    private var configurationTask: Task<Void, Error>?

    private init() {
        self.injectedQueue = nil
    }

    /// Creates an isolated SDK instance for testing.
    internal init(queue: AnalyticsEventQueue) {
        self.injectedQueue = queue
    }

    
    // MARK: - Configuration

    /// Configures the SDK once per application process.
    ///
    /// Concurrent callers wait for the same initialization task.
    /// Automatically persists one app_open event.
    /// No network request is performed during configuration.
    public func configure(
        _ configuration: AnalyticsConfiguration
    ) async throws {

        // Already configured successfully.
        guard !isConfigured else {
            return
        }

        // Another caller is configuring the SDK.
        // Wait for its result instead of starting again.
        if let configurationTask {
            try await configurationTask.value
            return
        }

        let task = Task { [self] in

            let queue: AnalyticsEventQueue

            if let injectedQueue {
                queue = injectedQueue
            } else {
                queue = try AnalyticsEventQueue()
            }

            let apiClient = AnalyticsAPIClient(
                baseURL: configuration.baseURL
            )

            let installationManager = AnalyticsInstallationManager()

            let syncManager = AnalyticsSyncManager(
                configuration: configuration,
                queue: queue,
                apiClient: apiClient,
                installationManager: installationManager
            )

            // Persist app_open before completing initialization.
            let appOpenEvent = AnalyticsEvent(
                eventName: "app_open"
            )

            try await queue.enqueue(appOpenEvent)

            self.queue = queue
            self.syncManager = syncManager
            self.isConfigured = true
        }

        configurationTask = task

        do {
            try await task.value
            configurationTask = nil
        } catch {
            configurationTask = nil
            throw error
        }
    }


    // MARK: - Tracking

    /// Persists an analytics event in the local queue.
    ///
    /// Events are not sent immediately.
    public func track(
        _ eventName: String,
        sessionUUID: UUID? = nil,
        metadata: [String: String]? = nil
    ) async throws {

        guard let queue else {
            throw AnalyticsSDKError.notConfigured
        }

        let event = AnalyticsEvent(
            eventName: eventName,
            sessionUUID: sessionUUID,
            metadata: metadata
        )

        try await queue.enqueue(event)
    }

    // MARK: - Synchronization

    /// Manually synchronizes pending events.
    public func sync() async throws {

        guard let syncManager else {
            throw AnalyticsSDKError.notConfigured
        }

        await syncManager.sync()
    }
}

// MARK: - Errors

public enum AnalyticsSDKError: Error, Sendable {
    case notConfigured
}
