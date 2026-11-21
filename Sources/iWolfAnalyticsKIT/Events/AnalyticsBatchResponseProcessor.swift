//
//  AnalyticsBatchResponseProcessor.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//


import Foundation

/// Actions to apply after processing a successful batch response.
struct AnalyticsBatchProcessingResult: Sendable {

    let removeIDs: Set<UUID>
    let retryIDs: Set<UUID>
    let keepIDs: Set<UUID>
}

/// Validates individual rejections and resolves their actions.
enum AnalyticsBatchResponseProcessor {

    /// Returns nil when the backend response is inconsistent
    /// with the batch that was sent.
    static func process(
        batch: [QueuedAnalyticsEvent],
        response: AnalyticsAPIResponse
    ) -> AnalyticsBatchProcessingResult? {

        var rejectedIndices = Set<Int>()
        var rejectedIDs = Set<UUID>()

        var removeIDs = Set<UUID>()
        var retryIDs = Set<UUID>()
        var keepIDs = Set<UUID>()

        // Validate the entire response before applying actions.
        for rejection in response.data.rejected {

            guard batch.indices.contains(rejection.index) else {
                return nil
            }

            let event = batch[rejection.index].event

            guard event.id == rejection.eventUUID else {
                return nil
            }

            guard rejectedIndices.insert(rejection.index).inserted,
                  rejectedIDs.insert(rejection.eventUUID).inserted else {
                return nil
            }
        }

        // Resolve rejected events.
        for rejection in response.data.rejected {

            switch AnalyticsEventErrorHandler.handle(
                errorCode: rejection.code
            ) {

            case .remove:
                removeIDs.insert(rejection.eventUUID)

            case .retry:
                retryIDs.insert(rejection.eventUUID)

            case .keep:
                keepIDs.insert(rejection.eventUUID)
            }
        }

        // Events not rejected by the backend were accepted.
        for queuedEvent in batch {

            let id = queuedEvent.event.id

            if !rejectedIDs.contains(id) {
                removeIDs.insert(id)
            }
        }

        return AnalyticsBatchProcessingResult(
            removeIDs: removeIDs,
            retryIDs: retryIDs,
            keepIDs: keepIDs
        )
    }
}

