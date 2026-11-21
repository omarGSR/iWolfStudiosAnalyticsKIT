//
//  AnalyticsBatch.swift.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Represents a batch of analytics events sent to the backend.
public struct AnalyticsBatch: Encodable, Sendable {

    public let appKey: String
    public let installationUUID: UUID
    public let appVersion: String?
    public let osVersion: String?
    public let country: String?
    public let deviceIdentifier: String?
    public let events: [AnalyticsEvent]

    public init(
        appKey: String,
        installationUUID: UUID,
        appVersion: String? = nil,
        osVersion: String? = nil,
        country: String? = nil,
        deviceIdentifier: String? = nil,
        events: [AnalyticsEvent]
    ) {
        self.appKey = appKey
        self.installationUUID = installationUUID
        self.appVersion = Self.normalizedVersion(appVersion)
        self.osVersion = Self.normalizedVersion(osVersion)
        self.country = country
        self.deviceIdentifier = deviceIdentifier
        self.events = events
    }
    
    private static func normalizedVersion(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "unknown"
        }

        return value
    }

    enum CodingKeys: String, CodingKey {
        case appKey = "app_key"
        case installationUUID = "installation_uuid"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case country
        case deviceIdentifier = "device_identifier"
        case events
    }
}
