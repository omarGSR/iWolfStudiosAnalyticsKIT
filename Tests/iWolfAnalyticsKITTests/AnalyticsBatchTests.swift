//
//  AnalyticsBatchTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//


import Foundation
import Testing
@testable import iWolfAnalyticsKIT

@Suite("Analytics Batch")
struct AnalyticsBatchTests {

    @Test("Encode technical information")
    func encodeTechnicalInformation() throws {
        let batch = AnalyticsBatch(
            appKey: "io.iwolfstudios.AwakeNest.debug",
            installationUUID: UUID(
                uuidString: "550e8400-e29b-41d4-a716-446655440000"
            )!,
            appVersion: "1.0.0",
            osVersion: "26.1",
            country: "ES",
            deviceIdentifier: "Mac14,13",
            events: []
        )

        let data = try JSONEncoder().encode(batch)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["app_version"] as? String == "1.0.0")
        #expect(json["os_version"] as? String == "26.1")
        #expect(json["device_identifier"] as? String == "Mac14,13")
        #expect(json["country"] as? String == "ES")
    }

    @Test("Encode missing optional information")
    func encodeMissingOptionalInformation() throws {
        let batch = AnalyticsBatch(
            appKey: "io.iwolfstudios.AwakeNest.debug",
            installationUUID: UUID(),
            appVersion: nil,
            osVersion: nil,
            country: nil,
            deviceIdentifier: nil,
            events: []
        )

        let data = try JSONEncoder().encode(batch)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["app_version"] as? String == "unknown")
        #expect(json["os_version"] as? String == "unknown")
        #expect(json["country"] == nil)
        #expect(json["device_identifier"] == nil)
    }
}
