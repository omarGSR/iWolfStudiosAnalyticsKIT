//
//  AnalyticsEvent.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Represents an analytics event sent to the backend.
public struct AnalyticsEvent: Codable, Sendable, Identifiable {

    public let id: UUID
    public let sessionUUID: UUID?
    public let eventName: String
    public let occurredAt: Date
    public let metadata: [String: String]?

    public init(
        eventName: String,
        sessionUUID: UUID? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.sessionUUID = sessionUUID
        self.eventName = eventName
        self.occurredAt = Date()
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id = "event_uuid"
        case sessionUUID = "session_uuid"
        case eventName = "event_name"
        case occurredAt = "occurred_at"
        case metadata
    }
}
