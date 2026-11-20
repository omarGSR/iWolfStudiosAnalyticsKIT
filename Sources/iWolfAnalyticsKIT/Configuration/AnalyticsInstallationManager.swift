//
//  Untitled.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Manages the persistent installation identifier.
public actor AnalyticsInstallationManager {

    private let defaults: UserDefaults
    private let key = "iWolfAnalytics.installationUUID"

    private var cachedUUID: UUID?

    public init(suiteName: String? = nil) {
        if let suiteName {
            self.defaults = UserDefaults(suiteName: suiteName)!
        } else {
            self.defaults = .standard
        }
    }

    /// Returns the persistent UUID for this installation.
    public func installationUUID() -> UUID {

        if let cachedUUID {
            return cachedUUID
        }

        if let storedValue = defaults.string(forKey: key),
           let uuid = UUID(uuidString: storedValue) {
            cachedUUID = uuid
            return uuid
        }

        let uuid = UUID()

        defaults.set(uuid.uuidString, forKey: key)
        cachedUUID = uuid

        return uuid
    }
}
