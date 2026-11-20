//
//  AnalyticsAPIResponse.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Successful response from the Analytics API.
struct AnalyticsAPIResponse: Decodable, Sendable {

    let data: AnalyticsBatchResponse
}

/// Result of processing an analytics batch.
struct AnalyticsBatchResponse: Decodable, Sendable {

    let rejected: [AnalyticsRejectedEvent]
}

/// An individual event rejected by the backend.
struct AnalyticsRejectedEvent: Decodable, Sendable {

    let index: Int
    let eventUUID: UUID
    let code: String

    enum CodingKeys: String, CodingKey {
        case index
        case eventUUID = "event_uuid"
        case code
    }
}
