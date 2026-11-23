// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation

/// Public entry point for iWolf Analytics.
public actor iWolfAnalyticsKIT {

    // MARK: - Singleton

    public static let shared = iWolfAnalyticsKIT()

    // MARK: - Dependencies

    private let injectedQueue: AnalyticsEventQueue?
    private let injectedAPIClient: AnalyticsAPIClient?

    private var queue: AnalyticsEventQueue?
    private var syncManager: AnalyticsSyncManager?
    private var syncScheduler: AnalyticsSyncScheduler?

    // MARK: - State

    private var isConfigured = false
    private var configurationTask: Task<Void, Error>?

    private init() {
        self.injectedQueue = nil
        self.injectedAPIClient = nil
    }

    /// Creates an isolated SDK instance for testing.
    internal init(
        queue: AnalyticsEventQueue,
        apiClient: AnalyticsAPIClient? = nil
    ) {
        self.injectedQueue = queue
        self.injectedAPIClient = apiClient
    }

    // MARK: - Configuration

    /// Configures the SDK once per application process.
    ///
    /// Concurrent callers wait for the same initialization task.
    /// Automatically persists one app_open event.
    /// Starts the automatic synchronization scheduler.
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

            let apiClient = injectedAPIClient ?? AnalyticsAPIClient(
                baseURL: configuration.baseURL
            )

            let installationManager = AnalyticsInstallationManager()

            let syncManager = AnalyticsSyncManager(
                configuration: configuration,
                queue: queue,
                apiClient: apiClient,
                installationManager: installationManager
            )

            let syncScheduler = AnalyticsSyncScheduler(
                queue: queue,
                syncManager: syncManager,
                configuration: configuration
            )

            // Persist app_open before starting the scheduler.
            let appOpenEvent = AnalyticsEvent(
                eventName: "app_open"
            )

            try await queue.enqueue(appOpenEvent)
            
            // Check app update
            if let appUpdateEvent = await installationManager.needsAppUpdate() {
                try await queue.enqueue(appUpdateEvent)
                await installationManager.confirmAppVersion()
            }

            self.queue = queue
            self.syncManager = syncManager
            self.syncScheduler = syncScheduler
            
            self.isConfigured = true

            // Enable automatic synchronization.
            await syncScheduler.start()

            // Sync if there are events from a previous execution. We use two becouse the we just added a "app_open"
            await syncScheduler.syncIfNeeded(minEvents: 2)
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
    /// The scheduler decides when to synchronize.
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

        // Always persist before notifying the scheduler.
        try await queue.enqueue(event)

        // Notify the scheduler without blocking track().
        if let syncScheduler {
            Task {
                await syncScheduler.eventEnqueued()
            }
        }
    }

    // MARK: - Synchronization

    /// Manually synchronizes pending events.
    ///
    /// Manual synchronization is not restricted by the
    /// scheduler's event count or timing policy.
    public func sync() async throws {

        guard let syncManager else {
            throw AnalyticsSDKError.notConfigured
        }

        await syncManager.sync()
    }

    // MARK: - Application Lifecycle

    /// Re-evaluates pending events when the app becomes active.
    public func applicationDidBecomeActive() async {

        guard isConfigured else {
            return
        }

        await syncScheduler?.applicationDidBecomeActive()
    }

    /// Stops automatic synchronization.
    ///
    /// Does not remove persisted events.
    public func stopAutomaticSync() async {

        await syncScheduler?.stop()
    }

    /// Restarts automatic synchronization.
    ///
    /// Pending events are evaluated again.
    public func startAutomaticSync() async {

        guard isConfigured else {
            return
        }

        await syncScheduler?.start()
    }
}

// MARK: - Errors

public enum AnalyticsSDKError: Error, Sendable {
    case notConfigured
}
