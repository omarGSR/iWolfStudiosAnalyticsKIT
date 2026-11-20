//
//  AnalyticsInstallationManagerTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsInstallationManagerTests {

    @Test("Installation UUID persists between instances")
    func testUUIDPersistence() async throws {

        let suiteName = "test.analytics.\(UUID().uuidString)"

        defer {
            UserDefaults.standard.removePersistentDomain(
                forName: suiteName
            )
        }

        let firstManager = AnalyticsInstallationManager(
            suiteName: suiteName
        )

        let firstUUID = await firstManager.installationUUID()

        let secondManager = AnalyticsInstallationManager(
            suiteName: suiteName
        )

        let secondUUID = await secondManager.installationUUID()

        #expect(firstUUID == secondUUID)
    }

    @Test("Different installations have different UUIDs")
    func testDifferentInstallations() async {

        let firstSuite = "test.analytics.\(UUID().uuidString)"
        let secondSuite = "test.analytics.\(UUID().uuidString)"

        defer {
            UserDefaults.standard.removePersistentDomain(
                forName: firstSuite
            )

            UserDefaults.standard.removePersistentDomain(
                forName: secondSuite
            )
        }

        let firstManager = AnalyticsInstallationManager(
            suiteName: firstSuite
        )

        let secondManager = AnalyticsInstallationManager(
            suiteName: secondSuite
        )

        let firstUUID = await firstManager.installationUUID()
        let secondUUID = await secondManager.installationUUID()

        #expect(firstUUID != secondUUID)
    }

    @Test("Invalid stored UUID is replaced")
    func testInvalidUUID() async throws {

        let suiteName = "test.analytics.\(UUID().uuidString)"

        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(
            "invalid-uuid",
            forKey: "iWolfAnalytics.installationUUID"
        )

        let manager = AnalyticsInstallationManager(
            suiteName: suiteName
        )

        let uuid = await manager.installationUUID()

        let storedUUID = defaults.string(
            forKey: "iWolfAnalytics.installationUUID"
        )

        #expect(storedUUID == uuid.uuidString)
    }
}
