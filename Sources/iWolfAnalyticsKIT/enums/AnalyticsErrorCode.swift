//
//  AnalyticsErrorCode.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Error codes returned by the iWolf Analytics backend.
public enum AnalyticsErrorCode: String, Codable, Sendable {

    // MARK: - General

    case invalidJson = "invalid_json"
    case invalidRequest = "invalid_request"
    case missingRequiredField = "missing_required_field"
    case invalidFieldValue = "invalid_field_value"
    case invalidCountry = "invalid_country"

    // MARK: - Applications

    case invalidAppKey = "invalid_app_key"
    case applicationNotFound = "application_not_found"

    // MARK: - Events

    case batchLimitExceeded = "batch_limit_exceeded"
    case requestTooLarge = "request_too_large"
    case metadataLimitExceeded = "metadata_limit_exceeded"
    case invalidEventUUID = "invalid_event_uuid"
    case invalidSessionUUID = "invalid_session_uuid"
    case invalidEventName = "invalid_event_name"
    case invalidEventDate = "invalid_event_date"
    case invalidSessionReason = "invalid_session_reason"
    case invalidSessionMode = "invalid_session_mode"
    case emptyEvents = "empty_events"

    // MARK: - Security

    case unauthorized = "unauthorized"
    case forbidden = "forbidden"
    case rateLimitExceeded = "rate_limit_exceeded"

    // MARK: - Server

    case internalError = "internal_error"
    case serviceUnavailable = "service_unavailable"
}
