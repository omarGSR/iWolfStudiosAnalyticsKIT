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
    }

    // MARK: - Synchronization

    func sync() async {

        guard !isSyncing else {
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

        let availableSlots = max(
            0,
            configuration.maxSimultaneousRequests - activeBatchCount
        )

        guard availableSlots > 0 else {
            return []
        }

        let pendingEvents = await queue.peek(
            limit: configuration.batchSize * availableSlots,
            excluding: inFlightIDs.union(excludedIDs)
        )

        let batches = AnalyticsBatchSelector.select(
            from: pendingEvents,
            batchSize: configuration.batchSize,
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

        activeBatchCount = max(0, activeBatchCount - 1)
    }

    // MARK: - Private

    private func performSync() async {

        let initialBatches = await reserveBatches()

        guard !initialBatches.isEmpty else {
            return
        }

        // Prevent failed or rejected batches from being sent
        // repeatedly during the same synchronization cycle.
        var attemptedIDs = Set<UUID>()

        for batch in initialBatches {
            attemptedIDs.formUnion(batch.map { $0.event.id })
        }
        
        let installationUUID = await installationManager.installationUUID()

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

                await processResult(result)

                releaseBatch(result.batch)

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
    }

    // MARK: - Sending

    private struct BatchTaskResult: Sendable {
        let batch: [QueuedAnalyticsEvent]
        let result: Result<AnalyticsAPIResult, Error>
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
                events: batch.map { $0.event }
            )

            do {
                let response = try await apiClient.send(analyticsBatch)

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
    ) async {

        switch result.result {

        case .success(let response):

            switch response {

            case .success(let apiResponse):

                // Partial rejection handling comes next.
                // For now, only accept batches with no rejections.
                guard apiResponse.data.rejected.isEmpty else {
                    return
                }

                let acceptedIDs = Set(
                    result.batch.map { $0.event.id }
                )

                do {
                    try await queue.remove(ids: acceptedIDs)
                } catch {
                    // Events remain in the persistent queue.
                }

            case .httpError:
                // Global error handling comes next.
                break
            }

        case .failure:
            // Network errors remain queued for a future sync.
            break
        }
    }
}
