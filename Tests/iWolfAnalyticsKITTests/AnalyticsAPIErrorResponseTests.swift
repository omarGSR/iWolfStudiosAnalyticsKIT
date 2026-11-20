//
//  AnalyticsAPIErrorResponseTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation
import Testing
@testable import iWolfAnalyticsKIT

struct AnalyticsAPIErrorResponseTests {

    @Test("Decode invalid application key")
    func testInvalidAppKey() throws {

        let json = """
        {
            "error": {
                "code": "invalid_app_key",
                "message": "Unsupported application."
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIErrorResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.error.code == "invalid_app_key")
        #expect(response.error.message == "Unsupported application.")
    }

    @Test("Decode field validation error")
    func testInvalidFieldValue() throws {

        let json = """
        {
            "error": {
                "code": "invalid_field_value",
                "message": "Invalid installation_uuid."
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIErrorResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.error.code == "invalid_field_value")
        #expect(response.error.message == "Invalid installation_uuid.")
    }

    @Test("Decode unknown backend error code")
    func testUnknownErrorCode() throws {

        let json = """
        {
            "error": {
                "code": "future_backend_error",
                "message": "New validation error."
            }
        }
        """

        let response = try JSONDecoder().decode(
            AnalyticsAPIErrorResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.error.code == "future_backend_error")
    }

    @Test("Reject malformed global error response")
    func testMalformedResponse() {

        let json = """
        {
            "error": {
                "message": "Missing error code."
            }
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                AnalyticsAPIErrorResponse.self,
                from: Data(json.utf8)
            )
        }
    }
}
