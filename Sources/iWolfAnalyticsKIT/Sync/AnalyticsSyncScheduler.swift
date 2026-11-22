//
//  AnalyticsSyncScheduler.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation

/// Automatically schedules synchronization of queued events.
///
/// Decides when to synchronize, while AnalyticsSyncManager
/// handles sending batches and processing responses.
actor AnalyticsSyncScheduler {

    // MARK: - Dependencies

    private let queue: AnalyticsEventQueue
    private let syncManager: AnalyticsSyncManager
    private let policy: AnalyticsSyncPolicy

    // MARK: - State

    private var scheduledTask: Task<Void, Never>?
    private var isRunning = false
    private var evaluationGeneration: Int?
    private var needsEvaluation = false

    /// Prevents repeated automatic syncs when the queue
    /// makes no progress after a completed attempt.
    private var nextAttemptNotBefore: Date?

    /// Invalidates evaluations started before stop/restart.
    private var generation = 0

    // MARK: - Initialization

    init(
        queue: AnalyticsEventQueue,
        syncManager: AnalyticsSyncManager,
        configuration: AnalyticsConfiguration
    ) {
        self.queue = queue
        self.syncManager = syncManager
        self.policy = AnalyticsSyncPolicy(configuration: configuration)
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else {
            return
        }

        generation += 1
        isRunning = true

        await requestEvaluation()
    }

    func stop() {
        generation += 1
        isRunning = false
        needsEvaluation = false
        nextAttemptNotBefore = nil

        cancelScheduledTask()
    }
    
    func syncIfNeeded(minEvents: Int = 1) async {
        guard isRunning, minEvents > 0 else {
            return
        }

        let currentGeneration = generation
        let pendingCount = await queue.count()

        guard isValid(currentGeneration),
              pendingCount >= minEvents else {
            return
        }

        let state = await syncManager.synchronizationState()

        guard isValid(currentGeneration),
              state.canSync(at: Date()) else {
            return
        }

        await syncManager.sync()
        await requestEvaluation()
    }

    // MARK: - Events

    /// Called after an event has been persisted.
    func eventEnqueued() async {
        guard isRunning else {
            return
        }

        await requestEvaluation()
    }

    /// Re-evaluates the queue when the app becomes active.
    func applicationDidBecomeActive() async {
        guard isRunning else {
            return
        }

        await requestEvaluation()
    }

    // MARK: - Evaluation Coordination

    private func requestEvaluation() async {

        guard isRunning else {
            return
        }

        needsEvaluation = true

        let currentGeneration = generation

        // Only one evaluation per generation.
        guard evaluationGeneration != currentGeneration else {
            return
        }

        evaluationGeneration = currentGeneration

        while isValid(currentGeneration) && needsEvaluation {

            needsEvaluation = false

            await evaluateOnce(
                generation: currentGeneration
            )
        }

        // An older evaluation must never clear the state
        // belonging to a newer scheduler generation.
        if evaluationGeneration == currentGeneration {
            evaluationGeneration = nil
        }
    }


    // MARK: - Evaluation

    private func evaluateOnce(
        generation expectedGeneration: Int
    ) async {

        cancelScheduledTask()

        guard isValid(expectedGeneration) else {
            return
        }

        guard let oldestDate =
            await queue.oldestEnqueuedAt() else {
            return
        }

        let pendingCount = await queue.count()
        let state = await syncManager.synchronizationState()

        guard isValid(expectedGeneration) else {
            return
        }

        let now = Date()

        let oldestAge = max(
            0,
            now.timeIntervalSince(oldestDate)
        )

        let allowedByManager = state.canSync(at: now)

        let allowedByCooldown: Bool

        if let nextAttemptNotBefore {
            allowedByCooldown = now >= nextAttemptNotBefore
        } else {
            allowedByCooldown = true
        }

        let shouldSync = policy.shouldSync(
            pendingEvents: pendingCount,
            effectiveBatchSize: state.effectiveBatchSize,
            oldestPendingAge: oldestAge,
            canSync: allowedByManager && allowedByCooldown
        )

        if shouldSync {

            await syncManager.sync()

            guard isValid(expectedGeneration) else {
                return
            }

            let remainingCount = await queue.count()

            guard isValid(expectedGeneration) else {
                return
            }

            if remainingCount >= pendingCount {

                // No progress: avoid immediately resending
                // events that the backend asked us to keep.
                nextAttemptNotBefore = Date()
                    .addingTimeInterval(policy.syncInterval)

            } else {

                nextAttemptNotBefore = nil
            }

            // Evaluate the remaining queue in a new iteration,
            // never through recursive calls.
            needsEvaluation = true
            return
        }

        // MARK: - Next Evaluation

        guard pendingCount > 0 else {
            return
        }

        // Permanent configuration/security failure.
        // Wait for an explicit resume/reconfiguration.
        guard !state.isStopped else {
            return
        }

        var nextDate: Date

        if pendingCount >= state.effectiveBatchSize {

            nextDate = now

        } else if pendingCount >= policy.minEventsToSync {

            nextDate = oldestDate.addingTimeInterval(
                policy.syncInterval
            )

        } else {

            nextDate = oldestDate.addingTimeInterval(
                policy.forcedSyncInterval
            )
        }

        // Respect the manager's global backoff.
        if let retryDate = state.nextRetryAt {
            nextDate = max(nextDate, retryDate)
        }

        // Respect the no-progress cooldown.
        if let cooldownDate = nextAttemptNotBefore {
            nextDate = max(nextDate, cooldownDate)
        }

        let delay = max(
            0.1,
            nextDate.timeIntervalSinceNow
        )

        scheduleEvaluation(
            after: delay,
            generation: expectedGeneration
        )
    }

    // MARK: - Scheduling

    private func scheduleEvaluation(
        after interval: TimeInterval,
        generation expectedGeneration: Int
    ) {

        scheduledTask = Task { [weak self] in

            do {
                try await Task.sleep(
                    for: .seconds(interval)
                )
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await self?.scheduledEvaluationFired(
                generation: expectedGeneration
            )
        }
    }

    private func scheduledEvaluationFired(
        generation expectedGeneration: Int
    ) async {

        guard isValid(expectedGeneration) else {
            return
        }

        scheduledTask = nil

        await requestEvaluation()
    }

    private func cancelScheduledTask() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    // MARK: - Validation

    private func isValid(
        _ expectedGeneration: Int
    ) -> Bool {
        isRunning && generation == expectedGeneration
    }
}
