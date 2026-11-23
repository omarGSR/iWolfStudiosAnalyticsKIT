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
    private let appVersion = "iWolfAnalytics.appVersion"

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
    
    public func needsAppUpdate() -> AnalyticsEvent? {
        guard let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !currentVersion.isEmpty else {
            return nil
        }

        guard let previousVersion = defaults.string(forKey: appVersion) else {
            // First launch: save version without generating an event.
            defaults.set(currentVersion, forKey: appVersion)
            return nil
        }

        guard previousVersion != currentVersion else {
            return nil
        }

        return AnalyticsEvent(
            eventName: "app_update",
            metadata: [
                "old_version": previousVersion,
                "new_version": currentVersion
            ]
        )
    }
    
    public func confirmAppVersion() {
        guard let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !currentVersion.isEmpty else {
            return
        }

        defaults.set(currentVersion, forKey: appVersion)
    }
}
