//
//  AnalyticsEventErrorHandler.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Action to perform after an individual event rejection.
enum AnalyticsEventErrorAction: Equatable, Sendable {

    /// Remove the event permanently from the queue.
    case remove

    /// Retry the event, incrementing its retry counter.
    case retry

    /// Preserve the event without incrementing retries.
    case keep
}

/// Resolves individual event rejection codes into actions.
enum AnalyticsEventErrorHandler {

    static func handle(
        errorCode: String
    ) -> AnalyticsEventErrorAction {

        guard let code = AnalyticsErrorCode(rawValue: errorCode) else {
            // Unknown event errors are treated as permanent rejections.
            return .remove
        }

        switch code {

        // MARK: - Temporary errors

        case .internalError,
             .serviceUnavailable,
             .rateLimitExceeded:
            return .retry

        // MARK: - Configuration / security errors

        case .invalidAppKey,
             .applicationNotFound,
             .unauthorized,
             .forbidden:
            return .keep

        // MARK: - Permanent event errors

        case .invalidEventUUID,
             .invalidSessionUUID,
             .invalidEventName,
             .invalidEventDate,
             .invalidSessionReason,
             .invalidSessionMode,
             .metadataLimitExceeded,
             .invalidFieldValue,
             .missingRequiredField:
            return .remove

        // MARK: - Other errors

        default:
            return .remove
        }
    }
}
