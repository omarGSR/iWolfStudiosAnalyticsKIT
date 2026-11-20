//
//  AnalyticsAPIResponseTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsAPIResponseTests {

    @Test("Decode successful response without rejected events")
    func testEmptyRejectedEvents() throws {

        let json = """
        {
            "data": {
                "rejected": []
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.data.rejected.isEmpty)
    }

    @Test("Decode rejected event with UUID and error code")
    func testRejectedEvent() throws {

        let eventUUID = UUID()

        let json = """
        {
            "data": {
                "rejected": [
                    {
                        "index": 0,
                        "event_uuid": "\(eventUUID.uuidString)",
                        "code": "invalid_session_uuid"
                    }
                ]
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.data.rejected.count == 1)
        #expect(response.data.rejected[0].index == 0)
        #expect(response.data.rejected[0].eventUUID == eventUUID)
        #expect(response.data.rejected[0].code == "invalid_session_uuid")
    }

    @Test("Decode unknown error code without failing")
    func testUnknownErrorCode() throws {

        let json = """
        {
            "data": {
                "rejected": [
                    {
                        "index": 0,
                        "event_uuid": "b8b68f91-741e-4e19-9db1-3e8c0f0a2007",
                        "code": "future_backend_error"
                    }
                ]
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIResponse.self,
            from: Data(json.utf8)
        )

        #expect(
            response.data.rejected[0].code == "future_backend_error"
        )
    }

    @Test("Reject malformed event UUID")
    func testInvalidEventUUID() {

        let json = """
        {
            "data": {
                "rejected": [
                    {
                        "index": 0,
                        "event_uuid": "not-a-valid-uuid",
                        "code": "invalid_event_uuid"
                    }
                ]
            }
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                AnalyticsAPIResponse.self,
                from: Data(json.utf8)
            )
        }
    }
}
