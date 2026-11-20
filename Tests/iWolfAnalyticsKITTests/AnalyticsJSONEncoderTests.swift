//
//  AnalyticsJSONEncoderTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsJSONEncoderTests {

    @Test("Batch encodes using backend field names")
    func testBatchEncoding() throws {

        let event = AnalyticsEvent(
            eventName: "session_started",
            metadata: [
                "mode": "mouse_nest"
            ]
        )

        let batch = AnalyticsBatch(
            appKey: "io.iwolfstudios.AwakeNest.debug",
            installationUUID: UUID(),
            appVersion: "1.0.0",
            osVersion: "macOS 26.0",
            country: "ES",
            events: [event]
        )

        let data = try AnalyticsJSONEncoder.encode(batch)

        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["app_key"] as? String == "io.iwolfstudios.AwakeNest.debug")
        #expect(json["app_version"] as? String == "1.0.0")
        #expect(json["country"] as? String == "ES")

        let events = try #require(json["events"] as? [[String: Any]])
        let firstEvent = try #require(events.first)

        #expect(firstEvent["event_name"] as? String == "session_started")
        #expect(firstEvent["event_uuid"] as? String != nil)
        #expect(firstEvent["occurred_at"] as? String != nil)

        let metadata = try #require(firstEvent["metadata"] as? [String: String])
        #expect(metadata["mode"] == "mouse_nest")
    }

    @Test("Nil country is omitted from JSON")
    func testNilCountry() throws {

        let batch = AnalyticsBatch(
            appKey: "test.app",
            installationUUID: UUID(),
            country: nil,
            events: []
        )

        let data = try AnalyticsJSONEncoder.encode(batch)

        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["country"] == nil)
    }
}
