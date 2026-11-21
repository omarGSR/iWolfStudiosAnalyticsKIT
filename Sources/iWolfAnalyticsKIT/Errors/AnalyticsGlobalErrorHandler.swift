//
//  AnalyticsGlobalErrorHandler.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Action to perform after a global API error.
enum AnalyticsGlobalErrorAction: Equatable, Sendable {

    /// Retry the batch later.
    case retry

    /// Stop synchronization and preserve queued events.
    case stop
    
    /// Stop synchronization and discard all queued events.
    case stopAndClear

    /// Retry with a smaller batch.
    case reduceBatchSize
}

/// Resolves global API errors into synchronization actions.
enum AnalyticsGlobalErrorHandler {

    static func handle(
        statusCode: Int?,
        errorCode: String?
    ) -> AnalyticsGlobalErrorAction {

        // Network errors (no HTTP response).
        guard let statusCode else {
            return .retry
        }

        // Server errors.
        if statusCode >= 500 {
            return .retry
        }

        // Rate limiting.
        if statusCode == 429 {
            return .retry
        }

        // Request exceeds the allowed size.
        if statusCode == 413 {
            return .reduceBatchSize
        }

        // Unknown errors must preserve the queue.
        guard let errorCode,
              let code = AnalyticsErrorCode(rawValue: errorCode)
        else {
            return .stop
        }

        switch code {

        case .requestTooLarge,
             .batchLimitExceeded:
            return .reduceBatchSize

        case .internalError,
             .serviceUnavailable,
             .rateLimitExceeded:
            return .retry

        case .invalidAppKey,
             .applicationNotFound:
            return .stopAndClear

        case .invalidJson,
             .invalidRequest,
             .missingRequiredField,
             .invalidFieldValue,
             .invalidCountry,
             .unauthorized,
             .forbidden,
             .emptyEvents:
            return .stop

        default:
            // Event-specific errors returned globally.
            // Preserve the batch until the problem is resolved.
            return .stop
        }
    }
}
