//
//  AnalyticsSyncManager.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Coordinates the synchronization of queued analytics events.
actor AnalyticsSyncManager {

    // MARK: - Dependencies

    private let configuration: AnalyticsConfiguration
    private let queue: AnalyticsEventQueue
    private let apiClient: AnalyticsAPIClient
    private let installationManager: AnalyticsInstallationManager

    // MARK: - State

    private var isSyncing = false
    private var inFlightIDs = Set<UUID>()
    private var activeBatchCount = 0

    private var syncState: AnalyticsSyncState

    // MARK: - Initialization

    init(
        configuration: AnalyticsConfiguration,
        queue: AnalyticsEventQueue,
        apiClient: AnalyticsAPIClient,
        installationManager: AnalyticsInstallationManager = AnalyticsInstallationManager()
    ) {
        self.configuration = configuration
        self.queue = queue
        self.apiClient = apiClient
        self.installationManager = installationManager

        self.syncState = AnalyticsSyncState(
            batchSize: configuration.batchSize
        )
    }

    
    // MARK: - Testing Support

    func synchronizationState() -> AnalyticsSyncState {
        syncState
    }

    
    // MARK: - Synchronization

    func sync() async {

        guard !isSyncing,
              syncState.canSync() else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        await performSync()
    }

    // MARK: - Batch Selection

    func reserveBatches(
        excluding excludedIDs: Set<UUID> = []
    ) async -> [[QueuedAnalyticsEvent]] {

        guard syncState.canSync() else {
            return []
        }

        let availableSlots = max(
            0,
            configuration.maxSimultaneousRequests - activeBatchCount
        )

        guard availableSlots > 0 else {
            return []
        }

        let batchSize = syncState.effectiveBatchSize

        let pendingEvents = await queue.peek(
            limit: batchSize * availableSlots,
            excluding: inFlightIDs.union(excludedIDs)
        )

        let batches = AnalyticsBatchSelector.select(
            from: pendingEvents,
            batchSize: batchSize,
            maxBatches: availableSlots
        )

        for batch in batches {
            for queuedEvent in batch {
                inFlightIDs.insert(queuedEvent.event.id)
            }
        }

        activeBatchCount += batches.count

        return batches
    }

    func releaseBatch(_ batch: [QueuedAnalyticsEvent]) {

        guard !batch.isEmpty else {
            return
        }

        for queuedEvent in batch {
            inFlightIDs.remove(queuedEvent.event.id)
        }

        activeBatchCount = max(
            0,
            activeBatchCount - 1
        )
    }

    // MARK: - Private

 
    private func performSync() async {

        let initialBatches = await reserveBatches()

        guard !initialBatches.isEmpty else {
            return
        }

        var attemptedIDs = Set<UUID>()

        for batch in initialBatches {
            attemptedIDs.formUnion(
                batch.map { $0.event.id }
            )
        }

        let installationUUID =
            await installationManager.installationUUID()

        var highestFailurePriority: GlobalFailurePriority?
        var hadSuccessfulResponse = false

        await withTaskGroup(
            of: BatchTaskResult.self
        ) { group in

            for batch in initialBatches {
                addBatch(
                    batch,
                    installationUUID: installationUUID,
                    to: &group
                )
            }

            while let result = await group.next() {

                let outcome = await processResult(result)

                switch outcome {

                case .success:
                    hadSuccessfulResponse = true

                case .globalFailure(let action):

                    let priority = GlobalFailurePriority(action)

                    if let current = highestFailurePriority {
                        if priority.rawValue > current.rawValue {
                            highestFailurePriority = priority
                        }
                    } else {
                        highestFailurePriority = priority
                    }
                }

                releaseBatch(result.batch)

                // Stop scheduling new batches after the first
                // global failure, but drain in-flight requests.
                guard highestFailurePriority == nil else {
                    continue
                }

                let nextBatches = await reserveBatches(
                    excluding: attemptedIDs
                )

                for batch in nextBatches {

                    attemptedIDs.formUnion(
                        batch.map { $0.event.id }
                    )

                    addBatch(
                        batch,
                        installationUUID: installationUUID,
                        to: &group
                    )
                }
            }
        }

        // Apply one global action per synchronization cycle.
        if let priority = highestFailurePriority {
            syncState.apply(priority.action)
        } else if hadSuccessfulResponse {
            syncState.recordSuccess()
        }
    }


    // MARK: - Sending

    private struct BatchTaskResult: Sendable {
        let batch: [QueuedAnalyticsEvent]
        let result: Result<AnalyticsAPIResult, Error>
    }

    private enum BatchProcessingOutcome {
        case success
        case globalFailure(AnalyticsGlobalErrorAction)
    }

    
    private enum GlobalFailurePriority: Int {
        case retry = 1
        case reduceBatchSize = 2
        case stop = 3

        init(_ action: AnalyticsGlobalErrorAction) {
            switch action {
            case .retry:
                self = .retry
            case .reduceBatchSize:
                self = .reduceBatchSize
            case .stop:
                self = .stop
            }
        }

        var action: AnalyticsGlobalErrorAction {
            switch self {
            case .retry:
                return .retry
            case .reduceBatchSize:
                return .reduceBatchSize
            case .stop:
                return .stop
            }
        }
    }

    private func addBatch(
        _ batch: [QueuedAnalyticsEvent],
        installationUUID: UUID,
        to group: inout TaskGroup<BatchTaskResult>
    ) {

        let apiClient = self.apiClient
        let configuration = self.configuration

        group.addTask {

            let analyticsBatch = AnalyticsBatch(
                appKey: configuration.appKey,
                installationUUID: installationUUID,
                appVersion: AnalyticsDeviceInfo.appVersion,
                osVersion: AnalyticsDeviceInfo.osVersion,
                country: AnalyticsDeviceInfo.country,
                deviceIdentifier: AnalyticsDeviceInfo.deviceIdentifier,
                events: batch.map { $0.event }
            )

            do {
                let response = try await apiClient.send(
                    analyticsBatch
                )

                return BatchTaskResult(
                    batch: batch,
                    result: .success(response)
                )

            } catch {
                return BatchTaskResult(
                    batch: batch,
                    result: .failure(error)
                )
            }
        }
    }

    // MARK: - Response Processing

    private func processResult(
        _ result: BatchTaskResult
    ) async -> BatchProcessingOutcome {

        switch result.result {

        case .success(let response):

            switch response {

            case .success(let apiResponse):

                guard let processingResult =
                    AnalyticsBatchResponseProcessor.process(
                        batch: result.batch,
                        response: apiResponse
                    )
                else {
                    // Invalid HTTP 200 response.
                    // Preserve all events.
                    return .globalFailure(.retry)
                }

                do {
                    try await queue.apply(
                        processingResult,
                        maxRetries: configuration.maxRetries
                    )

                    return .success

                } catch {
                    // Persistence failed.
                    // Preserve the queue.
                    return .globalFailure(.retry)
                }

            case .httpError(
                let statusCode,
                let errorCode,
                _,
                _
            ):

                let action = AnalyticsGlobalErrorHandler.handle(
                    statusCode: statusCode,
                    errorCode: errorCode
                )

                return .globalFailure(action)
            }

        case .failure:

            // Network or decoding failure.
            // Event retry counters remain unchanged.
            return .globalFailure(.retry)
        }
    }

}
